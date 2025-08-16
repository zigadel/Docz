const std = @import("std");
const hot = @import("hot_reload.zig");

// Import core pieces directly to avoid circular/self import of "docz"
const Tokenizer = @import("../src/parser/tokenizer.zig");
const Parser = @import("../src/parser/parser.zig");
const Renderer = @import("../src/renderer/html.zig");
const HtmlExport = @import("html_export");

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

    pub fn listenAndServe(self: *PreviewServer, port: u16) !void {
        const addr = try std.net.Address.parseIp4("127.0.0.1", port);
        var tcp = try std.net.Address.listen(addr, .{ .reuse_address = true });
        defer tcp.deinit();

        std.debug.print("🔎 web-preview listening on http://127.0.0.1:{d}\n", .{port});

        // (Optional) background watcher — harmless if the file doesn't exist.
        _ = try std.Thread.spawn(.{}, pollFileAndBroadcast, .{ &self.broadcaster, "docs/SPEC.dcz", 250 });

        while (true) {
            const net_conn = try tcp.accept();
            defer net_conn.stream.close();

            var read_buf: [16 * 1024]u8 = undefined;
            var http = std.http.Server.init(net_conn, &read_buf);

            var req = http.receiveHead() catch |e| {
                std.debug.print("❌ receiveHead error: {s}\n", .{@errorName(e)});
                continue;
            };

            const path = req.head.target;
            const bare_path = stripQuery(path);

            // Silence hot marker + favicon noise
            const is_hot = std.mem.eql(u8, bare_path, "/__docz_hot.txt");
            const is_favicon = std.mem.eql(u8, bare_path, "/favicon.ico");
            if (!is_hot and !is_favicon) {
                std.debug.print("→ {s} {s}\n", .{ @tagName(req.head.method), path });
            }

            self.handle(&http, &req) catch |e| {
                std.debug.print("❌ handler error: {s}\n", .{@errorName(e)});
                const msg = "Internal server error\n";
                _ = req.respond(msg, .{
                    .status = .internal_server_error,
                    .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
                }) catch {};
            };
        }
    }

    fn handle(self: *PreviewServer, _srv: *std.http.Server, req: *std.http.Server.Request) !void {
        _ = _srv;
        const path = req.head.target;

        if (std.mem.startsWith(u8, path, "/third_party/")) {
            // Strip the leading slash and serve from repo root
            const rel = path[1..]; // "third_party/…"
            std.debug.print("  route=third_party hit={s}\n", .{rel});
            return self.serveFile(req, rel);
        }

        if (std.mem.eql(u8, stripQuery(path), "/ping")) {
            return req.respond("pong\n", .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
            });
        }

        if (std.mem.eql(u8, stripQuery(path), "/favicon.ico")) {
            return req.respond("", .{
                .status = .no_content,
                .extra_headers = &.{.{ .name = "Cache-Control", .value = "no-store" }},
            });
        }

        // Placeholder SSE endpoint (non-streaming to match your Zig stdlib)
        if (std.mem.eql(u8, stripQuery(path), "/hot")) {
            return handleSSE(req);
        }

        if (std.mem.startsWith(u8, path, "/render")) {
            const raw = queryParam(path, "path") orelse "docs/SPEC.dcz";
            const fs_path = try urlDecode(self.allocator, raw);
            defer self.allocator.free(fs_path);
            std.debug.print("  route=/render path={s}\n", .{fs_path});
            return self.serveRenderedFragment(req, fs_path);
        }

        if (std.mem.startsWith(u8, path, "/view")) {
            const raw = queryParam(path, "path") orelse "docs/SPEC.dcz";
            const fs_path = try urlDecode(self.allocator, raw);
            defer self.allocator.free(fs_path);
            std.debug.print("  route=/view path={s}\n", .{fs_path});
            return self.serveRenderedDcz(req, fs_path);
        }

        const safe_rel = try sanitizePath(self.allocator, path);
        defer self.allocator.free(safe_rel);

        if (safe_rel.len == 0 or std.mem.eql(u8, safe_rel, ".")) {
            // index shell that redirects to /view?path=...
            return self.serveIndex(req);
        }

        const candidate_a = try join2(self.allocator, self.doc_root, safe_rel);
        defer self.allocator.free(candidate_a);
        if (fileExists(candidate_a)) {
            if (!std.mem.endsWith(u8, safe_rel, "__docz_hot.txt")) {
                std.debug.print("  route=static hit={s}\n", .{candidate_a});
            }
            return self.serveFile(req, candidate_a);
        }

        const rel_html = try withHtmlExt(self.allocator, safe_rel);
        defer self.allocator.free(rel_html);
        const candidate_b = try join2(self.allocator, self.doc_root, rel_html);
        defer self.allocator.free(candidate_b);
        if (fileExists(candidate_b)) {
            std.debug.print("  route=static hit={s}\n", .{candidate_b});
            return self.serveFile(req, candidate_b);
        }

        std.debug.print("  route=fallback → index\n", .{});
        return self.serveIndex(req);
    }

    // Non-streaming placeholder so it compiles on your Zig
    fn handleSSE(req: *std.http.Server.Request) !void {
        const body = "SSE endpoint placeholder (streaming disabled in this build).\n";
        return req.respond(body, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/plain; charset=utf-8" },
                .{ .name = "Cache-Control", .value = "no-cache" },
                .{ .name = "Connection", .value = "close" },
            },
        });
    }

    fn serveIndex(self: *PreviewServer, req: *std.http.Server.Request) !void {
        const html = try buildIndexHtml(self.allocator);
        defer self.allocator.free(html);

        var cl_buf: [32]u8 = undefined;
        const cl_str = fmtU64(&cl_buf, html.len);

        return req.respond(html, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Content-Length", .value = cl_str },
                .{ .name = "Cache-Control", .value = "no-cache" },
                .{ .name = "Connection", .value = "close" },
            },
        });
    }

    fn serveRenderedDcz(self: *PreviewServer, req: *std.http.Server.Request, fs_path: []const u8) !void {
        const A = self.allocator;

        const t0 = std.time.milliTimestamp();
        const input = readFileAlloc(A, fs_path) catch |e| {
            std.debug.print("  read FAIL {s}: {s}\n", .{ fs_path, @errorName(e) });
            const body = try std.fmt.allocPrint(A, "<pre>Failed to read {s}: {s}</pre>", .{ fs_path, @errorName(e) });
            defer A.free(body);
            return req.respond(body, .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/html; charset=utf-8" }},
            });
        };
        defer A.free(input);
        std.debug.print("  read ok {s} ({d} bytes, {d}ms)\n", .{ fs_path, input.len, std.time.milliTimestamp() - t0 });

        const t1 = std.time.milliTimestamp();
        const tokens = Tokenizer.tokenize(input, A) catch |e| {
            const msg = try std.fmt.allocPrint(
                A,
                "<pre>Tokenizer error: {s}\n(unterminated directive params or invalid syntax?)</pre>",
                .{@errorName(e)},
            );
            defer A.free(msg);
            return req.respond(msg, .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/html; charset=utf-8" }},
            });
        };
        defer {
            Tokenizer.freeTokens(A, tokens);
            A.free(tokens);
        }
        std.debug.print("  tokenize ok ({d} tokens, {d}ms)\n", .{ tokens.len, std.time.milliTimestamp() - t1 });

        const t2 = std.time.milliTimestamp();
        var ast = try Parser.parse(tokens, A);
        defer ast.deinit();
        std.debug.print("  parse ok ({d} nodes, {d}ms)\n", .{ ast.children.items.len, std.time.milliTimestamp() - t2 });

        const t3 = std.time.milliTimestamp();
        const html = try HtmlExport.exportHtml(&ast, A);
        defer A.free(html);
        std.debug.print("  render ok ({d} bytes, {d}ms)\n", .{ html.len, std.time.milliTimestamp() - t3 });

        return req.respond(html, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Cache-Control", .value = "no-cache" },
            },
        });
    }

    fn serveRenderedFragment(self: *PreviewServer, req: *std.http.Server.Request, fs_path: []const u8) !void {
        const A = self.allocator;

        const t0 = std.time.milliTimestamp();
        const input = readFileAlloc(A, fs_path) catch |e| {
            std.debug.print("  read FAIL {s}: {s}\n", .{ fs_path, @errorName(e) });
            const body = try std.fmt.allocPrint(A, "<pre>Failed to read {s}: {s}</pre>", .{ fs_path, @errorName(e) });
            defer A.free(body);
            return req.respond(body, .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/html; charset=utf-8" }},
            });
        };
        defer A.free(input);
        std.debug.print("  read ok {s} ({d} bytes, {d}ms)\n", .{ fs_path, input.len, std.time.milliTimestamp() - t0 });

        const t1 = std.time.milliTimestamp();
        const tokens = Tokenizer.tokenize(input, A) catch |e| {
            const msg = try std.fmt.allocPrint(
                A,
                "<pre>Tokenizer error: {s}\n(unterminated directive params or invalid syntax?)</pre>",
                .{@errorName(e)},
            );
            defer A.free(msg);
            return req.respond(msg, .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/html; charset=utf-8" }},
            });
        };
        defer {
            Tokenizer.freeTokens(A, tokens);
            A.free(tokens);
        }
        std.debug.print("  tokenize ok ({d} tokens, {d}ms)\n", .{ tokens.len, std.time.milliTimestamp() - t1 });

        const t2 = std.time.milliTimestamp();
        var ast = try Parser.parse(tokens, A);
        defer ast.deinit();
        std.debug.print("  parse ok ({d} nodes, {d}ms)\n", .{ ast.children.items.len, std.time.milliTimestamp() - t2 });

        const t3 = std.time.milliTimestamp();
        const full = try Renderer.renderHTML(&ast, A);
        defer A.free(full);
        std.debug.print("  render ok ({d} bytes, {d}ms)\n", .{ full.len, std.time.milliTimestamp() - t3 });

        const t4 = std.time.milliTimestamp();
        const frag = try extractBodyFragment(A, full);
        defer A.free(frag);
        std.debug.print("  extract body ok ({d} bytes, {d}ms)\n", .{ frag.len, std.time.milliTimestamp() - t4 });

        return req.respond(frag, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Cache-Control", .value = "no-cache" },
            },
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

        var cl_buf: [32]u8 = undefined;
        const cl_str = fmtU64(&cl_buf, n);

        return req.respond(buf[0..n], .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = ctype },
                .{ .name = "Content-Length", .value = cl_str },
            },
        });
    }
};

/////////////////////////////
//   Helper functions     //
/////////////////////////////

fn fmtU64(buf: *[32]u8, v: u64) []const u8 {
    // 32 bytes is more than enough for any u64 in base-10
    return std.fmt.bufPrint(buf, "{d}", .{v}) catch unreachable;
}

fn trimTrailingSlash(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var end = s.len;
    while (end > 0 and s[end - 1] == '/') end -= 1;
    return allocator.dupe(u8, s[0..end]);
}

/// Prevent path traversal. Returns normalized relative path without leading '/'.
fn sanitizePath(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var norm = std.ArrayList(u8).init(allocator);
    defer norm.deinit();
    try norm.ensureTotalCapacity(raw.len);
    for (raw) |c| try norm.append(if (c == '\\') '/' else c);

    var segs = std.ArrayList([]const u8).init(allocator);
    defer segs.deinit();

    var it = std.mem.splitScalar(u8, norm.items, '/');
    var depth: usize = 0;
    while (it.next()) |seg| {
        if (seg.len == 0 or std.mem.eql(u8, seg, ".")) continue;
        if (std.mem.eql(u8, seg, "..")) {
            if (depth == 0) return allocator.alloc(u8, 0);
            segs.items.len -= 1;
            depth -= 1;
            continue;
        }
        var ok = true;
        for (seg) |ch| {
            if (!(std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.')) {
                ok = false;
                break;
            }
        }
        if (!ok) return allocator.alloc(u8, 0);
        try segs.append(seg);
        depth += 1;
    }

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    var first = true;
    for (segs.items) |seg| {
        if (!first) try out.append('/');
        first = false;
        try out.appendSlice(seg);
    }
    return out.toOwnedSlice();
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
    std.fs.cwd().access(abs_path, .{}) catch return false;
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

fn urlDecode(allocator: std.mem.Allocator, enc: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, enc.len);
    var j: usize = 0;
    var i: usize = 0;
    while (i < enc.len) : (i += 1) {
        const c = enc[i];
        if (c == '%' and i + 2 < enc.len) {
            const h1 = enc[i + 1];
            const h2 = enc[i + 2];
            const v1 = hexVal(h1) orelse blk: {
                out[j] = c;
                j += 1;
                break :blk null;
            };
            const v2 = hexVal(h2) orelse blk: {
                out[j] = c;
                j += 1;
                break :blk null;
            };
            if (v1 != null and v2 != null) {
                out[j] = (@as(u8, v1.?) << 4) | @as(u8, v2.?);
                j += 1;
                i += 2;
                continue;
            }
        }
        out[j] = c;
        j += 1;
    }
    return allocator.realloc(out, j);
}

fn hexVal(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(10 + (c - 'a')),
        'A'...'F' => @intCast(10 + (c - 'A')),
        else => null,
    };
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    return try f.readToEndAlloc(allocator, 1 << 26);
}

// Poll a file and broadcast "reload" on mtime change (kept for future SSE use).
fn pollFileAndBroadcast(b: *hot.Broadcaster, path: []const u8, ms: u64) !void {
    var last: u64 = 0;
    while (true) {
        const mt = fileMtime(path) catch 0;
        if (mt != 0 and mt != last) {
            if (last != 0) try b.broadcast("reload", path);
            last = mt;
        }
        std.Thread.sleep(ms * std.time.ns_per_ms);
    }
}

fn fileMtime(path: []const u8) !u64 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const s = try f.stat();
    return @intCast(s.mtime);
}

/// Extract inner <body>…</body> from full HTML; if no <body>, return whole.
fn extractBodyFragment(allocator: std.mem.Allocator, full: []const u8) ![]u8 {
    const open_idx = std.mem.indexOf(u8, full, "<body");
    if (open_idx == null) return allocator.dupe(u8, full);

    const after_open_gt = std.mem.indexOfScalarPos(u8, full, open_idx.?, '>') orelse return allocator.dupe(u8, full);
    const rest = full[after_open_gt + 1 ..];
    const close_idx_rel = std.mem.indexOf(u8, rest, "</body>");
    if (close_idx_rel == null) return allocator.dupe(u8, rest);

    const inner = rest[0..close_idx_rel.?];
    return allocator.dupe(u8, inner);
}

fn buildIndexHtml(allocator: std.mem.Allocator) ![]u8 {
    const tpl =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <meta charset="UTF-8" />
        \\  <meta name="viewport" content="width=device-width, initial-scale=1" />
        \\  <title>Docz Web Preview</title>
        \\  <script>
        \\    (function () {
        \\      // Allow ?path=... override; default to docs/SPEC.dcz
        \\      const qs = new URLSearchParams(location.search);
        \\      const path = qs.get('path') || 'docs/SPEC.dcz';
        \\      const url = '/view?path=' + encodeURIComponent(path);
        \\      // Use replace() so Back button doesn’t bounce through the index shell
        \\      location.replace(url);
        \\    })();
        \\  </script>
        \\</head>
        \\<body>
        \\  <noscript>
        \\    <p>Preview requires JS to redirect. Open <code>/view?path=docs/SPEC.dcz</code>.</p>
        \\  </noscript>
        \\</body>
        \\</html>
    ;
    return allocator.dupe(u8, tpl);
}
