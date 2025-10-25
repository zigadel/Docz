const std = @import("std");
const web = @import("web_preview");

// ---- small helpers ---------------------------------------------------------

fn writeAllStream(s: *std.net.Stream, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = try s.write(bytes[off..]);
        if (n == 0) return error.Unexpected; // peer closed; treat as error on this snapshot
        off += n;
    }
}

fn readAll(s: *std.net.Stream, A: std.mem.Allocator) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(A);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = s.read(tmp[0..]) catch |e| switch (e) {
            // On this Zig version, EOF is signaled by n == 0 (no error).
            // Only WouldBlock is in the error set; Interrupted isn't.
            error.WouldBlock => continue,
            else => return e,
        };
        if (n == 0) break;
        try out.appendSlice(A, tmp[0..n]);
    }
    return out.toOwnedSlice(A);
}

fn httpGet(port: u16, path: []const u8, A: std.mem.Allocator) ![]u8 {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    var sock = try std.net.tcpConnectToAddress(addr);
    defer sock.close();

    var req = std.ArrayListUnmanaged(u8){};
    defer req.deinit(A);
    try req.appendSlice(A, "GET ");
    try req.appendSlice(A, path);
    try req.appendSlice(A, " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n");

    try writeAllStream(&sock, req.items);
    return readAll(&sock, A);
}

fn status(bytes: []const u8) !u16 {
    const nl = std.mem.indexOf(u8, bytes, "\r\n") orelse return error.BadFormat;
    const line = bytes[0..nl];
    const sp1 = std.mem.indexOfScalar(u8, line, ' ') orelse return error.BadFormat;
    const sp2 = std.mem.indexOfScalarPos(u8, line, sp1 + 1, ' ') orelse return error.BadFormat;
    return @intCast(try std.fmt.parseInt(u16, line[sp1 + 1 .. sp2], 10));
}

// ---- the smoke test --------------------------------------------------------

test "docz preview CLI smoke: starts, serves /healthz, stops" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const port: u16 = try web.findFreePort();

    // Build argv: docz preview --no-open --port <port>
    var port_buf: [16]u8 = undefined;
    const port_s = try std.fmt.bufPrint(&port_buf, "{d}", .{port});

    var child = std.process.Child.init(&[_][]const u8{
        "docz", "preview", "--no-open", "--port", port_s,
    }, A);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    // Provide auto-stop in case our /__docz_stop doesn't land.
    var env = try std.process.getEnvMap(A);
    defer env.deinit();
    try env.put("DOCZ_TEST_AUTOSTOP_MS", "2500");
    child.env_map = &env; // pass a pointer per this Zig snapshot's API

    try child.spawn();
    defer {
        // make sure we don't leak a process if the test fails early
        _ = child.kill() catch {};
        _ = child.wait() catch {};
    }

    // Give the server a brief moment to bind
    std.Thread.sleep(200 * std.time.ns_per_ms);

    // Probe /healthz (retry once if we raced the bind)
    const resp = httpGet(port, "/healthz", A) catch blk: {
        std.Thread.sleep(250 * std.time.ns_per_ms);
        break :blk try httpGet(port, "/healthz", A);
    };
    defer A.free(resp);
    try std.testing.expectEqual(@as(u16, 200), try status(resp));

    // Ask it to stop cleanly
    const stop_resp = try httpGet(port, "/__docz_stop", A);
    defer A.free(stop_resp);

    const term = try child.wait();
    try std.testing.expect(term == .Exited and term.Exited == 0);
}
