const std = @import("std");
const hot = @import("hot_reload.zig");
const docz = @import("docz");

/// Writes SSE bytes to an in-flight streaming HTTP response.
const SinkWrap = struct {
    res_ptr: *std.http.Server.Response,

    fn make(self: *SinkWrap) hot.Sink {
        return .{ .ctx = self, .writeFn = write };
    }

    fn write(ctx: *anyopaque, bytes: []const u8) !void {
        var self: *SinkWrap = @ptrCast(@alignCast(ctx));
        try self.res_ptr.writer().writeAll(bytes);
        try self.res_ptr.res.flush();
    }
};

/// Minimal HTTP preview server with:
/// - Static file serving from `doc_root`
/// - Index fallback that embeds an iframe to /view?path=docs/SPEC.dcz
/// - /view?path=... that renders .dcz → HTML via Docz core
/// - SSE endpoint '/_events' wired to Broadcaster; file mtime poller triggers "reload"
pub const PreviewServer = struct {
    allocator: std.mem.Allocator,
    doc_root: []const u8,
    broadcaster: hot.Broadcaster,

    pub fn init(allocator: std.mem.Allocator, doc_root: []const u8) !PreviewServer {
        const trimmed = try trimTrailingSlash(allocator, doc_root);
        errdefer allocator.free(trimmed);

        return .{
            .allocator = allocator,
            .doc_root = trimmed,
            .broadcaster = hot.Broadcaster.init(allocator),
        };
    }

    pub fn deinit(self: *PreviewServer) void {
        self.broadcaster.deinit();
        self.allocator.free(self.doc_root);
    }

    /// Blocks forever; Ctrl-C to stop. Serves HTTP on 127.0.0.1:port
    pub fn listenAndServe(self: *PreviewServer, port: u16) !void {
        var server = std.http.Server.init(self.allocator, .{ .reuse_address = true });
        defer server.deinit();

        try server.listen(.{ .address = try std.net.Address.parseIp4("127.0.0.1", port) });
        std.debug.print("🔎 web-preview listening on http://127.0.0.1:{d}\n", .{port});

        // Watch the default SPEC file for hot-reload; harmless if missing
        _ = try std.Thread.spawn(.{}, pollFileAndBroadcast, .{ &self.broadcaster, "docs/SPEC.dcz", 250 });

        while (true) {
            var conn = try server.accept(.{ .allocator = self.allocator });
            defer conn.deinit();
            if (conn.state != .ready) continue;

            var req = try conn.receiveHead();
            defer req.deinit();

            try self.handle(&conn, &req);
        }
    }

    fn handle(self: *PreviewServer, conn: *std.http.Server.Connection, req: *std.http.Server.Request) !void {
        _ = conn; // silence 'unused parameter'
        const path = req.head.target;

        // SSE endpoint
        if (std.mem.eql(u8, stripQuery(path), "/_events")) {
            return self.handleSSE(req);
        }

        // Live DCZ render endpoint: /view?path=docs/SPEC.dcz
        if (std.mem.startsWith(u8, path, "/view")) {
            const maybe = queryParam(path, "path");
            const fs_path = maybe orelse "docs/SPEC.dcz";
            return self.serveRenderedDcz(req, fs_path);
        }

        // Static file serving with simple routing and safe path handling
        const safe_rel = try sanitizePath(self.allocator, path);
        defer self.allocator.free(safe_rel);

        if (safe_rel.len == 0 or std.mem.eql(u8, safe_rel, ".")) {
            return self.serveIndex(req);
        }

        // candidate A: /doc_root/<safe_rel>
        const candidate_a = try join2(self.allocator, self.doc_root, safe_rel);
        defer self.allocator.free(candidate_a);

        if (fileExists(candidate_a)) {
            return self.serveFile(req, candidate_a);
        }

        // candidate B: append ".html"
        const rel_html = try withHtmlExt(self.allocator, safe_rel);
        defer self.allocator.free(rel_html);

        const candidate_b = try join2(self.allocator, self.doc_root, rel_html);
        defer self.allocator.free(candidate_b);

        if (fileExists(candidate_b)) {
            return self.serveFile(req, candidate_b);
        }

        // fallback
        return self.serveIndex(req);
    }

    fn handleSSE(self: *PreviewServer, req: *std.http.Server.Request) !void {
        // Prepare streaming response
        var res = try req.respondStreaming(.{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/event-stream" },
                .{ .name = "Cache-Control", .value = "no-cache" },
                .{ .name = "Connection", .value = "keep-alive" },
                .{ .name = "Access-Control-Allow-Origin", .value = "*" },
            },
        });
        defer res.finish();

        // Build a sink that writes to the streaming response
        var wrap = SinkWrap{ .res_ptr = &res };

        const id = try self.broadcaster.add(wrap.make());
        // Initial hello
        try self.broadcaster.broadcast("hello", "connected");

        // Keep alive until client is pruned/removed
        while (true) {
            std.time.sleep(500 * std.time.ns_per_ms);
            if (!isClientStillRegistered(&self.broadcaster, id)) break;
        }

        _ = self.broadcaster.remove(id);
    }

    fn serveIndex(self: *PreviewServer, req: *std.http.Server.Request) !void {
        const html = try buildIndexHtml(self.allocator);
        defer self.allocator.free(html);

        return req.respond(.{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Cache-Control", .value = "no-cache" },
            },
            .body = html,
        });
    }

    fn serveRenderedDcz(self: *PreviewServer, req: *std.http.Server.Request, fs_path: []const u8) !void {
        const A = self.allocator;

        // Read file
        const input = readFileAlloc(A, fs_path) catch |e| {
            return req.respond(.{
                .status = .ok,
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                },
                .body = try std.fmt.allocPrint(A, "<pre>Failed to read {s}: {s}</pre>", .{ fs_path, @errorName(e) }),
            });
        };
        defer A.free(input);

        // DCZ -> tokens -> AST
        const tokens = try docz.Tokenizer.tokenize(input, A);
        defer {
            docz.Tokenizer.freeTokens(A, tokens);
            A.free(tokens);
        }

        var ast = try docz.Parser.parse(tokens, A);
        defer ast.deinit();

        // AST -> HTML (public HTML renderer)
        const html = try docz.Renderer.renderHTML(&ast, A);
        defer A.free(html);

        return req.respond(.{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Cache-Control", .value = "no-cache" },
            },
            .body = html,
        });
    }

    fn serveFile(self: *PreviewServer, req: *std.http.Server.Request, abs_path: []const u8) !void {
        var file = try std.fs.cwd().openFile(abs_path, .{});
        defer file.close();

        const stat = try file.stat();
        const buf = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(buf);

        const n = try file.readAll(buf);
        const ctype = mimeFromPath(abs_path);

        return req.respond(.{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = ctype },
                .{ .name = "Content-Length", .value = try u64ToTmp(self.allocator, n) },
            },
            .body = buf[0..n],
        });
    }
};

/////////////////////////////
//   Helper functions     //
/////////////////////////////

fn u64ToTmp(allocator: std.mem.Allocator, v: u64) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{v});
}

fn trimTrailingSlash(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var end = s.len;
    while (end > 0 and s[end - 1] == '/') end -= 1;
    return allocator.dupe(u8, s[0..end]);
}

/// Prevent path traversal. Returns a normalized relative path without leading '/'.
/// "/" or "" => ""
fn sanitizePath(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    // Normalize slashes to '/'
    var norm = std.ArrayList(u8).init(allocator);
    defer norm.deinit();
    try norm.ensureTotalCapacity(raw.len);
    for (raw) |c| try norm.append(if (c == '\\') '/' else c);

    // Build stack of safe segments; reject traversal above root
    var segs = std.ArrayList([]const u8).init(allocator);
    defer segs.deinit();

    var it = std.mem.splitScalar(u8, norm.items, '/');
    var depth: usize = 0;
    while (it.next()) |seg| {
        if (seg.len == 0 or std.mem.eql(u8, seg, ".")) continue;

        if (std.mem.eql(u8, seg, "..")) {
            if (depth == 0) {
                // Attempt to climb above root → reject the whole path
                return allocator.alloc(u8, 0);
            }
            // Pop one segment
            segs.items.len -= 1;
            depth -= 1;
            continue;
        }

        // Optional: allow only reasonable characters in segments
        var ok = true;
        for (seg) |ch| {
            if (!(std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.')) {
                ok = false;
                break;
            }
        }
        if (!ok) {
            // Bad segment → reject
            return allocator.alloc(u8, 0);
        }

        try segs.append(seg);
        depth += 1;
    }

    // Join back with '/'
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var first = true;
    for (segs.items) |seg| {
        if (!first) try out.append('/');
        first = false;
        try out.appendSlice(seg);
    }

    return out.toOwnedSlice(); // caller frees
}

fn withHtmlExt(allocator: std.mem.Allocator, rel: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}.html", .{rel});
}

fn join2(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]const u8 {
    if (a.len == 0) return allocator.dupe(u8, b);
    if (b.len == 0) return allocator.dupe(u8, a);
    if (a[a.len - 1] == '/') return std.fmt.allocPrint(allocator, "{s}{s}", .{ a, b });
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ a, b });
}

fn fileExists(abs_path: []const u8) bool {
    std.fs.cwd().access(abs_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return false,
            else => return false,
        }
    };
    return true;
}

fn mimeFromPath(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".htm")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".js")) return "text/javascript; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) return "image/jpeg";
    if (std.mem.endsWith(u8, path, ".gif")) return "image/gif";
    if (std.mem.endsWith(u8, path, ".txt")) return "text/plain; charset=utf-8";
    return "application/octet-stream";
}

fn stripQuery(p: []const u8) []const u8 {
    return p[0 .. std.mem.indexOfScalar(u8, p, '?') orelse p.len];
}

fn queryParam(target: []const u8, key: []const u8) ?[]const u8 {
    const qpos = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    var it = std.mem.splitScalar(u8, target[qpos + 1 ..], '&');
    while (it.next()) |kv| {
        if (kv.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, kv, '=') orelse continue;
        if (std.mem.eql(u8, kv[0..eq], key)) return kv[eq + 1 ..];
    }
    return null;
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    return try f.readToEndAlloc(allocator, 1 << 26);
}

// Poll a file and broadcast "reload" on mtime change
fn pollFileAndBroadcast(b: *hot.Broadcaster, path: []const u8, ms: u64) !void {
    var last: u64 = 0;
    while (true) {
        const mt = fileMtime(path) catch 0;
        if (mt != 0 and mt != last) {
            if (last != 0) b.broadcast("reload", path);
            last = mt;
        }
        std.time.sleep(ms * std.time.ns_per_ms);
    }
}

fn fileMtime(path: []const u8) !u64 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const s = try f.stat();
    return @intCast(s.mtime);
}

fn buildIndexHtml(allocator: std.mem.Allocator) ![]u8 {
    const tpl =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <meta charset="UTF-8" />
        \\  <meta name="viewport" content="width=device-width, initial-scale=1" />
        \\  <title>Docz Web Preview</title>
        \\  <style>
        \\    html, body { margin: 0; padding: 0; height: 100%; }
        \\    .bar { background: #111; color: #eee; padding: 10px 12px; font: 14px system-ui, sans-serif; display:flex; gap:8px; align-items:center }
        \\    .bar input { min-width: 420px; }
        \\    #frame { border: 0; width: 100%; height: calc(100vh - 46px); }
        \\  </style>
        \\</head>
        \\<body>
        \\  <div class="bar">
        \\    <strong>Docz web-preview</strong>
        \\    <form id="f" action="/view" method="get" target="frame">
        \\      <input id="p" type="text" name="path" value="docs/SPEC.dcz" />
        \\      <button>Open</button>
        \\    </form>
        \\  </div>
        \\  <iframe id="frame" name="frame" src="/view?path=docs/SPEC.dcz"></iframe>
        \\  <script>
        \\    const es = new EventSource('/_events');
        \\    es.addEventListener('hello', () => console.log('[docz] sse connected'));
        \\    es.addEventListener('reload', () => {
        \\      const fr = document.getElementById('frame');
        \\      const url = new URL(fr.src, location.href);
        \\      url.searchParams.set('_', Date.now()); // cache-bust
        \\      fr.src = url.toString();
        \\    });
        \\  </script>
        \\</body>
        \\</html>
    ;
    return allocator.dupe(u8, tpl);
}

fn isClientStillRegistered(bc: *const hot.Broadcaster, id: u64) bool {
    for (bc.clients.items) |c| {
        if (c.id == id) return true;
    }
    return false;
}

/////////////////////////////
//         Tests          //
/////////////////////////////

test "sanitizePath normalizes and removes traversal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const a = try sanitizePath(A, "/../etc/passwd");
    defer A.free(a);
    try std.testing.expectEqualStrings("", a);

    const b = try sanitizePath(A, "/foo//bar/./baz");
    defer A.free(b);
    try std.testing.expectEqualStrings("foo/bar/baz", b);

    const c = try sanitizePath(A, "///alpha/../beta");
    defer A.free(c);
    try std.testing.expectEqualStrings("beta", c);
}

test "withHtmlExt & join2" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const h = try withHtmlExt(A, "page");
    defer A.free(h);
    try std.testing.expectEqualStrings("page.html", h);

    const j = try join2(A, "/root", "page.html");
    defer A.free(j);
    try std.testing.expectEqualStrings("/root/page.html", j);
}

test "mimeFromPath basics" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", mimeFromPath("x.html"));
    try std.testing.expectEqualStrings("text/css; charset=utf-8", mimeFromPath("x.css"));
    try std.testing.expectEqualStrings("image/png", mimeFromPath("x.png"));
    try std.testing.expectEqualStrings("application/octet-stream", mimeFromPath("x.bin"));
}

test "buildIndexHtml contains SSE bootstrap and iframe" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const html = try buildIndexHtml(A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "EventSource('/_events')") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "iframe") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "/view?path=docs/SPEC.dcz") != null);
}
