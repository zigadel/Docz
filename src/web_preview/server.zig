const std = @import("std");
const builtin = @import("builtin");
const utils_fs = @import("utils_fs");

// Import sibling hot-reload as a module (not by relative path)
const hot = @import("web_preview_hot");

// Depend on docz public API, not individual source files
const docz = @import("docz");
const Tokenizer = docz.Tokenizer;
const Parser = docz.Parser;
const Renderer = docz.Renderer;

const LogMode = enum { plain, json };

fn getenvOwnedOrNull(a: std.mem.Allocator, key: []const u8) ?[]u8 {
    return std.process.getEnvVarOwned(a, key) catch |e| switch (e) {
        error.EnvironmentVariableNotFound => null,
        else => null,
    };
}

fn chooseLogMode(a: std.mem.Allocator) LogMode {
    if (getenvOwnedOrNull(a, "DOCZ_LOG")) |v| {
        defer a.free(v);
        if (std.ascii.eqlIgnoreCase(v, "json")) return .json;
    }
    return .plain;
}

fn jsonEscapeInto(buf: *std.ArrayListUnmanaged(u8), s: []const u8, A: std.mem.Allocator) !void {
    // minimal escape: quotes, backslashes, and common control chars
    for (s) |c| switch (c) {
        '"' => try buf.appendSlice(A, "\\\""),
        '\\' => try buf.appendSlice(A, "\\\\"),
        '\n' => try buf.appendSlice(A, "\\n"),
        '\r' => try buf.appendSlice(A, "\\r"),
        '\t' => try buf.appendSlice(A, "\\t"),
        else => try buf.append(A, c),
    };
}

fn logServerJSON(event: []const u8, fields: []const struct { []const u8, []const u8 }) void {
    // Build: {"ts":..., "ev":"...", "k":"v", ...}
    var buf = std.ArrayListUnmanaged(u8){};
    const A = std.heap.page_allocator;
    defer buf.deinit(A);

    const ts = std.time.milliTimestamp();

    _ = buf.appendSlice(A, "{\"ts\":") catch return;

    var ts_buf: [32]u8 = undefined;
    const ts_s = std.fmt.bufPrint(&ts_buf, "{d}", .{ts}) catch return;
    _ = buf.appendSlice(A, ts_s) catch return;

    _ = buf.appendSlice(A, ",\"ev\":\"") catch return;
    jsonEscapeInto(&buf, event, A) catch return;
    _ = buf.appendSlice(A, "\"") catch return;

    for (fields) |kv| {
        _ = buf.appendSlice(A, ",\"") catch return;
        _ = buf.appendSlice(A, kv[0]) catch return;
        _ = buf.appendSlice(A, "\":\"") catch return;
        jsonEscapeInto(&buf, kv[1], A) catch return;
        _ = buf.appendSlice(A, "\"") catch return;
    }

    _ = buf.appendSlice(A, "}\n") catch return;

    // In this Zig build, std.debug.print is the portable way to write to stderr.
    std.debug.print("{s}", .{buf.items});
}

fn decU64(n: u64, buf: *[24]u8) []const u8 {
    return std.fmt.bufPrint(buf, "{d}", .{n}) catch unreachable;
}

// ----------------------------
// Minimal HTTP primitives
// ----------------------------
const Header = struct { name: []const u8, value: []const u8 };

const Status = enum(u16) {
    ok = 200,
    partial_content = 206,
    no_content = 204,
    not_modified = 304,
    range_not_satisfiable = 416,
    internal_server_error = 500,
};

fn statusReason(s: Status) []const u8 {
    return switch (s) {
        .ok => "OK",
        .partial_content => "Partial Content",
        .no_content => "No Content",
        .not_modified => "Not Modified",
        .range_not_satisfiable => "Range Not Satisfiable",
        .internal_server_error => "Internal Server Error",
    };
}

const RespondOpts = struct {
    status: Status = .ok,
    extra_headers: []const Header = &.{},
};

const Request = struct {
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    method: []const u8,
    target: []const u8,
    headers: []const u8, // raw header bytes including final CRLFCRLF (best-effort)

    fn respond(self: *Request, body: []const u8, opts: RespondOpts) !void {
        const code = @intFromEnum(opts.status);
        const reason = statusReason(opts.status);

        var len_buf: [24]u8 = undefined;
        const cl = decU64(body.len, &len_buf);

        const A = self.allocator;

        const status_line = try std.fmt.allocPrint(A, "HTTP/1.1 {d} {s}\r\n", .{ code, reason });
        defer A.free(status_line);
        try streamWriteAllCompat(self.stream, status_line);

        const cl_line = try std.fmt.allocPrint(A, "Content-Length: {s}\r\n", .{cl});
        defer A.free(cl_line);
        try streamWriteAllCompat(self.stream, cl_line);

        for (opts.extra_headers) |h| {
            const hline = try std.fmt.allocPrint(A, "{s}: {s}\r\n", .{ h.name, h.value });
            defer A.free(hline);
            try streamWriteAllCompat(self.stream, hline);
        }

        try streamWriteAllCompat(self.stream, "Connection: close\r\n\r\n");

        // HEAD: advertise length but do not send body
        if (!std.mem.eql(u8, self.method, "HEAD")) {
            try streamWriteAllCompat(self.stream, body);
        }
    }
};

// --- compat: write/read loops on sockets ---
fn writeAllCompat(w: anytype, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = try w.write(bytes[off..]);
        if (n == 0) return error.EndOfStream;
        off += n;
    }
}

fn streamWriteAllCompat(s: *std.net.Stream, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = try s.write(bytes[off..]);
        if (n == 0) return error.EndOfStream;
        off += n;
    }
}

// --- compat: read from TCP sockets via OS recv (avoids Windows ReadFile(87))
fn readStreamCompat(stream: *std.net.Stream, buf: []u8) !usize {
    if (builtin.os.tag == .windows) {
        const ws2 = std.os.windows.ws2_32;

        const ret: c_int = ws2.recv(
            stream.handle,
            buf.ptr,
            @as(c_int, @intCast(buf.len)),
            0,
        );
        if (ret == ws2.SOCKET_ERROR) {
            const werr = ws2.WSAGetLastError();
            const code: u16 = @intFromEnum(werr);
            return switch (code) {
                10035 => error.WouldBlock, // WSAEWOULDBLOCK
                10004 => error.Interrupted, // WSAEINTR
                10054 => error.ConnectionResetByPeer, // WSAECONNRESET
                else => error.Unexpected,
            };
        }
        return @as(usize, @intCast(ret));
    } else {
        const n = try std.posix.recv(stream.handle, buf, 0);
        return @as(usize, n);
    }
}

// ---- Minimal request reader (first line + best-effort headers), tolerant on Windows
fn receiveRequest(alloc: std.mem.Allocator, stream: *std.net.Stream) !Request {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(alloc);

    const max_header_bytes: usize = 64 * 1024;
    const start_ms = std.time.milliTimestamp();
    const retry_budget_ms: i64 = 1800;

    // Read until we at least have a first line
    var have_first_line = false;
    while (!have_first_line and buf.items.len < max_header_bytes) {
        var tmp: [2048]u8 = undefined;
        const n = readStreamCompat(stream, tmp[0..]) catch |e| switch (e) {
            error.WouldBlock, error.Interrupted, error.ConnectionResetByPeer, error.Unexpected => {
                if (std.time.milliTimestamp() - start_ms < retry_budget_ms) {
                    std.Thread.sleep(150 * std.time.ns_per_ms);
                    continue;
                }
                return error.BadRequest;
            },
        };
        if (n == 0) break;
        try buf.appendSlice(alloc, tmp[0..n]);
        if (std.mem.indexOfScalar(u8, buf.items, '\n') != null) have_first_line = true;
    }
    if (buf.items.len == 0) return error.BadRequest;

    // Split out first line
    const nl_i_opt = std.mem.indexOfScalar(u8, buf.items, '\n');
    const line_end = nl_i_opt orelse buf.items.len;
    const line_raw = buf.items[0..line_end];
    const first = if (line_raw.len > 0 and line_raw[line_raw.len - 1] == '\r')
        line_raw[0 .. line_raw.len - 1]
    else
        line_raw;

    var it = std.mem.tokenizeScalar(u8, first, ' ');
    const m = it.next() orelse "GET";
    const t = it.next() orelse "/";

    // If we didn't already capture CRLFCRLF, keep reading headers
    var have_end = std.mem.endsWith(u8, buf.items, "\r\n\r\n");
    while (!have_end and buf.items.len < max_header_bytes) {
        var tmp2: [2048]u8 = undefined;
        const n2 = readStreamCompat(stream, tmp2[0..]) catch |e| switch (e) {
            error.WouldBlock, error.Interrupted, error.ConnectionResetByPeer, error.Unexpected => {
                if (std.time.milliTimestamp() - start_ms < retry_budget_ms) {
                    std.Thread.sleep(100 * std.time.ns_per_ms);
                    continue;
                }
                break; // best-effort; we'll parse what we have
            },
        };
        if (n2 == 0) break;
        try buf.appendSlice(alloc, tmp2[0..n2]);
        have_end = std.mem.indexOf(u8, buf.items, "\r\n\r\n") != null;
    }

    // Extract raw header bytes AFTER the first line up to CRLFCRLF (if present)
    var headers_slice: []const u8 = &.{};
    if (std.mem.indexOf(u8, buf.items, "\r\n\r\n")) |end_hdr| {
        if (line_end < end_hdr + 4 and line_end + 1 <= buf.items.len) {
            const start_hdr = line_end + 1; // after LF
            headers_slice = try alloc.dupe(u8, buf.items[start_hdr .. end_hdr + 4]);
        }
    }

    const method = try alloc.dupe(u8, m);
    const target = try alloc.dupe(u8, t);
    buf.deinit(alloc);

    return .{
        .allocator = alloc,
        .stream = stream,
        .method = method,
        .target = target,
        .headers = headers_slice,
    };
}

/// Test helper: find a free TCP port on 127.0.0.1 by probing the user-ephemeral range.
pub fn findFreePort() !u16 {
    var p: u32 = 49152;
    while (p <= 65535) : (p += 1) {
        const try_port: u16 = @intCast(p);
        const addr_try = std.net.Address.parseIp4("127.0.0.1", try_port) catch continue;

        // MUST be var, not const, so we can call deinit()
        var probe = std.net.Address.listen(addr_try, .{ .reuse_address = true }) catch {
            continue;
        };
        probe.deinit();

        return try_port;
    }
    return error.AddressInUse;
}

// ----------------------------
// Preview server
// ----------------------------

pub const PreviewServer = struct {
    allocator: std.mem.Allocator,
    doc_root: []const u8,
    broadcaster: hot.Broadcaster,
    stop_requested: bool = false, // TEST-ONLY stop flag to exit the accept loop gracefully
    log_mode: LogMode = .plain,

    pub fn init(allocator: std.mem.Allocator, doc_root: []const u8) !PreviewServer {
        const trimmed = try trimTrailingSlash(allocator, doc_root);
        errdefer allocator.free(trimmed);
        return .{
            .allocator = allocator,
            .doc_root = trimmed,
            .broadcaster = hot.Broadcaster.init(allocator),
            .log_mode = chooseLogMode(allocator),
        };
    }

    pub fn deinit(self: *PreviewServer) void {
        self.broadcaster.deinit();
        self.allocator.free(self.doc_root);
    }

    /// Like listenAndServe, but if `port` is 0 it will auto-select a free ephemeral port.
    /// Returns the actual bound port. Useful for tests to avoid collisions.
    pub fn listenAndServeAuto(self: *PreviewServer, port: u16) !u16 {
        var chosen_port: u16 = port;
        if (chosen_port == 0) {
            // Choose an ephemeral port in the user range [49152..65535].
            var p: u32 = 49152;
            while (p <= 65535) : (p += 1) {
                const try_port: u16 = @intCast(p);
                const addr_try = std.net.Address.parseIp4("127.0.0.1", try_port) catch continue;
                const this_test = std.net.Address.listen(addr_try, .{ .reuse_address = true }) catch {
                    continue;
                };
                // Success: immediately close test listener and use this port for real.
                this_test.deinit();
                chosen_port = try_port;
                break;
            }
            if (chosen_port == 0) return error.AddressInUse;
        }

        // Now run the canonical server loop on the chosen port.
        try self.listenAndServe(chosen_port);
        return chosen_port;
    }

    pub fn listenAndServe(self: *PreviewServer, port: u16) !void {
        const addr = try std.net.Address.parseIp4("127.0.0.1", port);
        var tcp = try std.net.Address.listen(addr, .{ .reuse_address = true });
        defer tcp.deinit();

        switch (self.log_mode) {
            .plain => std.debug.print("🔎 web-preview listening on http://127.0.0.1:{d}\n", .{port}),
            .json => logServerJSON("listen", &.{
                .{ "addr", "127.0.0.1" },
                .{ "port", blk: {
                    var b: [24]u8 = undefined;
                    break :blk std.fmt.bufPrint(&b, "{d}", .{port}) catch "0";
                } },
            }),
        }

        // --- TEST-ONLY: auto-stop after N ms if env var is set --------------
        const ms_opt: ?[]u8 = std.process.getEnvVarOwned(self.allocator, "DOCZ_TEST_AUTOSTOP_MS") catch null;
        if (ms_opt) |ms_s| {
            defer self.allocator.free(ms_s);
            const ms = std.fmt.parseInt(u64, ms_s, 10) catch 0;
            if (ms > 0) {
                _ = std.Thread.spawn(.{}, struct {
                    fn run(srv: *PreviewServer, p: u16, delay_ms: u64) void {
                        std.Thread.sleep(delay_ms * std.time.ns_per_ms);
                        srv.stop_requested = true;
                        pokeSelf(p) catch {};
                    }
                }.run, .{ self, port, ms }) catch {};
            }
        }

        // Hot-reload poller (best-effort)
        _ = std.Thread.spawn(.{}, pollFileAndBroadcast, .{ &self.broadcaster, "docs/SPEC.dcz", 250 }) catch {};

        while (true) {
            const net_conn = tcp.accept() catch |e| switch (e) {
                error.ConnectionAborted, error.ConnectionResetByPeer => continue,
                else => return e,
            };
            defer net_conn.stream.close();

            var req = receiveRequest(self.allocator, @constCast(&net_conn.stream)) catch |e| {
                if (e != error.BadRequest) {
                    std.debug.print("❌ receiveRequest error: {s}\n", .{@errorName(e)});
                }
                continue;
            };
            defer {
                self.allocator.free(req.method);
                self.allocator.free(req.target);
                if (req.headers.len != 0) self.allocator.free(req.headers);
            }

            const path = req.target;
            const bare_path = stripQuery(path);

            const is_hot = std.mem.eql(u8, bare_path, "/__docz_hot.txt");
            const is_favicon = std.mem.eql(u8, bare_path, "/favicon.ico");
            if (!is_hot and !is_favicon) {
                const pfx_len: usize = @min(path.len, @as(usize, 64));
                std.debug.print("→ {s} {s}\n", .{ path[0..pfx_len], path });
            }

            self.handle(&req) catch |he| {
                std.debug.print("❌ handler error: {s}\n", .{@errorName(he)});
                const msg = "Internal server error\n";
                _ = req.respond(msg, .{
                    .status = .internal_server_error,
                    .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
                }) catch {};
            };

            if (self.stop_requested) break;
        }
    }

    fn handle(self: *PreviewServer, req: *Request) !void {
        const path = req.target;

        if (std.mem.startsWith(u8, path, "/third_party/")) {
            const rel = path[1..];
            std.debug.print("  route=third_party hit={s}\n", .{rel});
            return self.serveFile(req, rel);
        }

        if (std.mem.eql(u8, stripQuery(path), "/ping")) {
            return req.respond("pong\n", .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
            });
        }

        // simple diagnostics endpoint for CI/health checks
        if (std.mem.eql(u8, stripQuery(path), "/healthz")) {
            const body = try std.fmt.allocPrint(self.allocator, "{{\"ok\":true,\"doc_root\":\"{s}\"}}", .{self.doc_root});
            defer self.allocator.free(body);
            return req.respond(body, .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json; charset=utf-8" }},
            });
        }

        if (std.mem.eql(u8, stripQuery(path), "/favicon.ico")) {
            return req.respond("", .{
                .status = .no_content,
                .extra_headers = &.{.{ .name = "Cache-Control", .value = "no-store" }},
            });
        }

        // test-only shutdown endpoint—flip flag so accept loop exits.
        if (std.mem.eql(u8, stripQuery(path), "/__docz_stop")) {
            self.stop_requested = true;
            return req.respond("stopping\n", .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
            });
        }

        // Placeholder SSE endpoint (non-streaming in this build)
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
            return self.serveIndex(req);
        }

        const candidate_a = try utils_fs.join2Fs(self.allocator, self.doc_root, safe_rel);
        defer self.allocator.free(candidate_a);
        if (utils_fs.fileExists(candidate_a)) {
            if (!std.mem.endsWith(u8, safe_rel, "__docz_hot.txt")) {
                std.debug.print("  route=static hit={s}\n", .{candidate_a});
            }
            return self.serveFile(req, candidate_a);
        }

        const rel_html = try withHtmlExt(self.allocator, safe_rel);
        defer self.allocator.free(rel_html);
        const candidate_b = try utils_fs.join2Fs(self.allocator, self.doc_root, rel_html);
        defer self.allocator.free(candidate_b);
        if (utils_fs.fileExists(candidate_b)) {
            std.debug.print("  route=static hit={s}\n", .{candidate_b});
            return self.serveFile(req, candidate_b);
        }

        std.debug.print("  route=fallback → index\n", .{});
        return self.serveIndex(req);
    }

    fn handleSSE(req: *Request) !void {
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

    fn serveIndex(self: *PreviewServer, req: *Request) !void {
        const html = try buildIndexHtml(self.allocator);
        defer self.allocator.free(html);

        return req.respond(html, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Cache-Control", .value = "no-cache" },
                .{ .name = "Connection", .value = "close" },
            },
        });
    }

    fn serveRenderedDcz(self: *PreviewServer, req: *Request, fs_path: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const A = arena.allocator();

        const t0 = std.time.milliTimestamp();
        const input = readFileAlloc(A, fs_path) catch |e| {
            std.debug.print("  read FAIL {s}: {s}\n", .{ fs_path, @errorName(e) });
            const body = try std.fmt.allocPrint(A, "<pre>Failed to read {s}: {s}</pre>", .{ fs_path, @errorName(e) });
            return req.respond(body, .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/html; charset=utf-8" }},
            });
        };
        std.debug.print("  read ok {s} ({d} bytes, {d}ms)\n", .{ fs_path, input.len, std.time.milliTimestamp() - t0 });

        const t1 = std.time.milliTimestamp();
        const tokens = Tokenizer.tokenize(input, A) catch |e| {
            const msg = try std.fmt.allocPrint(
                A,
                "<pre>Tokenizer error: {s}\n(unterminated directive params or invalid syntax?)</pre>",
                .{@errorName(e)},
            );
            return req.respond(msg, .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/html; charset=utf-8" }},
            });
        };
        defer Tokenizer.freeTokens(A, tokens);
        std.debug.print("  tokenize ok ({d} tokens, {d}ms)\n", .{ tokens.len, std.time.milliTimestamp() - t1 });

        const t2 = std.time.milliTimestamp();
        var ast = try Parser.parse(tokens, A);
        defer ast.deinit(A);
        std.debug.print("  parse ok ({d} nodes, {d}ms)\n", .{ ast.children.items.len, std.time.milliTimestamp() - t2 });

        const t3 = std.time.milliTimestamp();
        const html = try Renderer.renderHTML(&ast, A);
        std.debug.print("  render ok ({d} bytes, {d}ms)\n", .{ html.len, std.time.milliTimestamp() - t3 });

        return req.respond(html, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Cache-Control", .value = "no-cache" },
            },
        });
    }

    fn serveRenderedFragment(self: *PreviewServer, req: *Request, fs_path: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const A = arena.allocator();

        const t0 = std.time.milliTimestamp();
        const input = readFileAlloc(A, fs_path) catch |e| {
            std.debug.print("  read FAIL {s}: {s}\n", .{ fs_path, @errorName(e) });
            const body = try std.fmt.allocPrint(A, "<pre>Failed to read {s}: {s}</pre>", .{ fs_path, @errorName(e) });
            return req.respond(body, .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/html; charset=utf-8" }},
            });
        };
        std.debug.print("  read ok {s} ({d} bytes, {d}ms)\n", .{ fs_path, input.len, std.time.milliTimestamp() - t0 });

        const t1 = std.time.milliTimestamp();
        const tokens = Tokenizer.tokenize(input, A) catch |e| {
            const msg = try std.fmt.allocPrint(
                A,
                "<pre>Tokenizer error: {s}\n(unterminated directive params or invalid syntax?)</pre>",
                .{@errorName(e)},
            );
            return req.respond(msg, .{
                .status = .ok,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/html; charset=utf-8" }},
            });
        };
        defer Tokenizer.freeTokens(A, tokens);
        std.debug.print("  tokenize ok ({d} tokens, {d}ms)\n", .{ tokens.len, std.time.milliTimestamp() - t1 });

        const t2 = std.time.milliTimestamp();
        var ast = try Parser.parse(tokens, A);
        defer ast.deinit(A);
        std.debug.print("  parse ok ({d} nodes, {d}ms)\n", .{ ast.children.items.len, std.time.milliTimestamp() - t2 });

        const t3 = std.time.milliTimestamp();
        const full = try Renderer.renderHTML(&ast, A);
        std.debug.print("  render ok ({d} bytes, {d}ms)\n", .{ full.len, std.time.milliTimestamp() - t3 });

        const t4 = std.time.milliTimestamp();
        const frag = try extractBodyFragment(A, full);
        std.debug.print("  extract body ok ({d} bytes, {d}ms)\n", .{ frag.len, std.time.milliTimestamp() - t4 });

        return req.respond(frag, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Cache-Control", .value = "no-cache" },
            },
        });
    }

    fn serveFile(self: *PreviewServer, req: *Request, abs_path: []const u8) !void {
        var file = try std.fs.cwd().openFile(abs_path, .{});
        defer file.close();

        const stat = try file.stat();

        // Read file (simple, fine for tests and small assets)
        const body = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(body);
        const n = try file.readAll(body);

        const ctype = mimeFromPath(abs_path);
        const is_third_party =
            std.mem.indexOf(u8, abs_path, "third_party/") != null or
            std.mem.startsWith(u8, abs_path, "third_party/");
        const cache_header =
            if (is_third_party) "public, max-age=31536000, immutable" else "no-cache";

        // Weak ETag based on mtime + size
        const mtime_u64: u64 = @intCast(stat.mtime);
        const etag = try std.fmt.allocPrint(self.allocator, "W/\"{x}-{d}\"", .{ mtime_u64, stat.size });
        defer self.allocator.free(etag);

        // 304 Not Modified if client ETag matches
        if (headerValue(req.headers, "If-None-Match")) |inm| {
            if (std.mem.eql(u8, inm, etag)) {
                const extra_304 = [_]Header{
                    .{ .name = "ETag", .value = etag },
                    .{ .name = "Cache-Control", .value = cache_header },
                };
                return req.respond("", .{
                    .status = .not_modified,
                    .extra_headers = &extra_304,
                });
            }
        }

        // Single-range support
        var status: Status = .ok;
        var send_slice: []const u8 = body[0..n];
        var extra_headers: [5]Header = .{
            .{ .name = "Content-Type", .value = ctype },
            .{ .name = "Cache-Control", .value = cache_header },
            .{ .name = "ETag", .value = etag },
            .{ .name = "Accept-Ranges", .value = "bytes" },
            .{ .name = "Content-Range", .value = "" }, // only set for 206/416
        };
        var extra_len: usize = 4; // append Content-Range if used

        if (headerValue(req.headers, "Range")) |rng| {
            if (parseSingleRange(rng, @intCast(n))) |r| {
                const lo: usize = @intCast(r.start);
                const hi: usize = @intCast(r.end);
                if (lo <= hi and hi < n) {
                    send_slice = body[lo .. hi + 1];
                    const cr = try std.fmt.allocPrint(self.allocator, "bytes {d}-{d}/{d}", .{ r.start, r.end, n });
                    defer self.allocator.free(cr);
                    extra_headers[4] = .{ .name = "Content-Range", .value = cr };
                    extra_len = 5;
                    status = .partial_content;
                }
            } else {
                // Invalid or unsatisfiable → 416
                const cr_all = try std.fmt.allocPrint(self.allocator, "bytes */{d}", .{n});
                defer self.allocator.free(cr_all);
                extra_headers[4] = .{ .name = "Content-Range", .value = cr_all };
                extra_len = 5;
                return req.respond("", .{
                    .status = .range_not_satisfiable,
                    .extra_headers = extra_headers[0..extra_len],
                });
            }
        }

        return req.respond(send_slice, .{
            .status = status,
            .extra_headers = extra_headers[0..extra_len],
        });
    }
};

// ----------------------------
// Helpers
// ----------------------------

fn headerValueCI(headers: []const u8, name: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, headers, '\n');
    while (it.next()) |line_with_cr| {
        const line = if (line_with_cr.len > 0 and line_with_cr[line_with_cr.len - 1] == '\r')
            line_with_cr[0 .. line_with_cr.len - 1]
        else
            line_with_cr;

        if (line.len < name.len + 1) continue; // needs at least "name:"
        if (!std.ascii.startsWithIgnoreCase(line, name)) continue;
        if (line[name.len] != ':') continue;

        var v = line[name.len + 1 ..]; // after ':'
        while (v.len > 0 and (v[0] == ' ' or v[0] == '\t')) v = v[1..];
        return v;
    }
    return null;
}

fn headerValue(headers: []const u8, name_ci: []const u8) ?[]const u8 {
    if (headers.len == 0) return null;
    var it = std.mem.splitScalar(u8, headers, '\n');
    while (it.next()) |line_with_cr| {
        var line = line_with_cr;
        if (line.len == 0) continue;
        if (line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = line[0..colon];
        if (std.ascii.eqlIgnoreCase(key, name_ci)) {
            var v = line[colon + 1 ..];
            while (v.len > 0 and (v[0] == ' ' or v[0] == '\t')) v = v[1..];
            return v;
        }
    }
    return null;
}

const Range = struct { start: u64, end: u64 }; // inclusive

fn parseSingleRange(hval: []const u8, size: u64) ?Range {
    // Expect: "bytes=<start>-<end>" with either side optionally blank (suffix)
    if (!std.mem.startsWith(u8, hval, "bytes=")) return null;
    const spec = hval[6..];

    const dash = std.mem.indexOfScalar(u8, spec, '-') orelse return null;
    const a = spec[0..dash];
    const b = spec[dash + 1 ..];

    if (a.len == 0 and b.len == 0) return null;

    if (a.len == 0) {
        // suffix: last N bytes
        const n = std.fmt.parseInt(u64, b, 10) catch return null;
        if (n == 0) return null;
        const start: u64 = if (n >= size) 0 else size - n;
        const end: u64 = if (size == 0) 0 else size - 1;
        if (start > end) return null;
        return .{ .start = start, .end = end };
    } else {
        const start = std.fmt.parseInt(u64, a, 10) catch return null;
        const end: u64 = if (b.len == 0)
            (if (size == 0) 0 else size - 1)
        else
            (std.fmt.parseInt(u64, b, 10) catch return null);

        if (start >= size) return null;
        if (end < start) return null;

        const clamped_end = if (end >= size) size - 1 else end;
        return .{ .start = start, .end = clamped_end };
    }
}

fn trimTrailingSlash(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var end = s.len;
    while (end > 0 and s[end - 1] == '/') end -= 1;
    return allocator.dupe(u8, s[0..end]);
}

fn sanitizePath(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var norm = std.ArrayListUnmanaged(u8){};
    defer norm.deinit(allocator);
    try norm.ensureTotalCapacity(allocator, raw.len);
    for (raw) |c| try norm.append(allocator, if (c == '\\') '/' else c);

    var segs = std.ArrayListUnmanaged([]const u8){};
    defer segs.deinit(allocator);

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
        try segs.append(allocator, seg);
        depth += 1;
    }

    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    var first = true;
    for (segs.items) |seg| {
        if (!first) try out.append(allocator, '/');
        first = false;
        try out.appendSlice(allocator, seg);
    }
    return out.toOwnedSlice(allocator);
}

fn withHtmlExt(allocator: std.mem.Allocator, rel: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}.html", .{rel});
}

fn mimeFromPath(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html") or std.mem.endsWith(u8, path, ".htm"))
        return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".js")) return "text/javascript; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) return "image/jpeg";
    if (std.mem.endsWith(u8, path, ".gif")) return "image/gif";
    if (std.mem.endsWith(u8, path, ".txt")) return "text/plain; charset=utf-8";

    // useful extras
    if (std.mem.endsWith(u8, path, ".ico")) return "image/x-icon";
    if (std.mem.endsWith(u8, path, ".webp")) return "image/webp";
    if (std.mem.endsWith(u8, path, ".woff2")) return "font/woff2";
    if (std.mem.endsWith(u8, path, ".map")) return "application/json; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".wasm")) return "application/wasm";

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
    return std.fs.cwd().readFileAlloc(path, allocator, @enumFromInt(1 << 26));
}

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
        \\      const qs = new URLSearchParams(location.search);
        \\      const path = qs.get('path') || 'docs/SPEC.dcz';
        \\      const url = '/view?path=' + encodeURIComponent(path);
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

// Wake up accept() by making a quick local connection.
fn pokeSelf(port: u16) !void {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    var sock = try std.net.tcpConnectToAddress(addr);
    sock.close();
}
