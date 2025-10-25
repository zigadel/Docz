const std = @import("std");
const testing = std.testing;
const web = @import("web_preview");
const tnet = @import("test_net");

// --- Minimal helpers (mirroring your working pattern) ---

fn writeAllStream(s: *std.net.Stream, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = try s.write(bytes[off..]);
        if (n == 0) return error.EndOfStream;
        off += n;
    }
}

fn readAll(s: *std.net.Stream, A: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(A);

    const start_ms = std.time.milliTimestamp();
    const budget_ms: i64 = 1500;

    while (true) {
        var tmp: [4096]u8 = undefined;
        const n = s.read(&tmp) catch |e| switch (e) {
            error.WouldBlock => {
                if (std.time.milliTimestamp() - start_ms < budget_ms) {
                    std.Thread.sleep(5 * std.time.ns_per_ms);
                    continue;
                }
                break;
            },
            else => return e,
        };
        if (n == 0) break;
        try buf.appendSlice(A, tmp[0..n]);
    }
    return buf.toOwnedSlice(A);
}

fn parseStatus(raw: []const u8) ?u16 {
    const sp1 = std.mem.indexOfScalar(u8, raw, ' ') orelse return null;
    const sp2 = std.mem.indexOfScalarPos(u8, raw, sp1 + 1, ' ') orelse return null;
    return std.fmt.parseUnsigned(u16, raw[sp1 + 1 .. sp2], 10) catch null;
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

fn httpGet(
    A: std.mem.Allocator,
    port: u16,
    method: []const u8,
    path: []const u8,
    extra_headers: []const []const u8,
) !struct { status: u16, headers: []const u8, body: []const u8, raw: []u8 } {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    var sock = try std.net.tcpConnectToAddress(addr);
    defer sock.close();

    var req = std.ArrayListUnmanaged(u8){};
    defer req.deinit(A);
    try req.appendSlice(A, method);
    try req.appendSlice(A, " ");
    try req.appendSlice(A, path);
    try req.appendSlice(A, " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n");
    for (extra_headers) |h| try req.appendSlice(A, h);
    try req.appendSlice(A, "\r\n");

    try writeAllStream(&sock, req.items);

    const raw = try readAll(&sock, A);
    const split = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return error.BadResponse;
    const headers = raw[0 .. split + 2];
    const body = raw[split + 4 ..];
    const status = parseStatus(raw) orelse return error.BadResponse;

    return .{ .status = status, .headers = headers, .body = body, .raw = raw };
}

fn startServer(A: std.mem.Allocator, port: u16) !std.Thread {
    const srv_ptr = try A.create(web.PreviewServer);
    errdefer A.destroy(srv_ptr);

    srv_ptr.* = try web.PreviewServer.init(A, ".");
    return try std.Thread.spawn(.{}, struct {
        fn run(srv: *web.PreviewServer, alloc: std.mem.Allocator, p: u16) void {
            defer {
                srv.deinit();
                alloc.destroy(srv);
            }
            web.PreviewServer.listenAndServe(srv, p) catch {};
        }
    }.run, .{ srv_ptr, A, port });
}

fn stopServer(port: u16) !void {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    var s = try std.net.tcpConnectToAddress(addr);
    defer s.close();

    const req = "GET /__docz_stop HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n";
    try writeAllStream(&s, req);
}

// --------------------- TEST ---------------------

test "static .wasm served with application/wasm MIME type" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    try std.fs.cwd().makePath("tmp_assets");
    try std.fs.cwd().writeFile(.{ .sub_path = "tmp_assets/hello.wasm", .data = "\x00asm\x01\x00\x00\x00" });

    const port: u16 = try web.findFreePort();
    var th = try tnet.startServer(A, port);
    defer th.join();

    try web.waitForPort(port, 1000);

    var resp = try tnet.httpGet(A, port, "GET", "/tmp_assets/hello.wasm", &.{});
    defer A.free(resp.raw);

    try testing.expectEqual(@as(u16, 200), resp.status);
    const ct = tnet.headerValue(resp.headers, "Content-Type") orelse return error.MissingContentType;
    try testing.expect(std.mem.startsWith(u8, ct, "application/wasm"));

    tnet.stopServer(port);
}
