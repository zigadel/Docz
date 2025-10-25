const std = @import("std");
const builtin = @import("builtin");
const web = @import("web_preview");

// Public helpers for integration/e2e tests
pub fn writeAllStream(s: *std.net.Stream, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = try s.write(bytes[off..]);
        if (n == 0) return error.EndOfStream;
        off += n;
    }
}

pub fn readAllToEnd(alloc: std.mem.Allocator, s: *std.net.Stream) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(alloc);

    var tmp: [4096]u8 = undefined;

    var timer = try std.time.Timer.start();
    var last_progress_ns: u64 = timer.read();
    const stall_ns: u64 = 1_000_000_000; // 1s
    const total_ns: u64 = 3_000_000_000; // 3s cap

    while (true) {
        const n = if (builtin.os.tag == .windows) blk: {
            const ws2 = std.os.windows.ws2_32;
            const ret: c_int = ws2.recv(
                s.handle,
                tmp[0..].ptr,
                @as(c_int, @intCast(tmp.len)),
                0,
            );
            if (ret == 0) break; // EOF
            if (ret == ws2.SOCKET_ERROR) {
                const werr = ws2.WSAGetLastError();
                const code: u16 = @intFromEnum(werr);
                switch (code) {
                    10035 => break :blk @as(usize, 0), // WSAEWOULDBLOCK
                    10004 => break :blk @as(usize, 0), // WSAEINTR
                    10054 => break,                    // reset → EOF
                    else => return error.Unexpected,
                }
            }
            break :blk @as(usize, @intCast(ret));
        } else blk: {
            const got = std.posix.recv(s.handle, tmp[0..], 0) catch |e| switch (e) {
                error.WouldBlock, error.Interrupted => 0,
                error.ConnectionResetByPeer => 0,
                else => return e,
            };
            break :blk @as(usize, got);
        };

        if (n > 0) {
            try out.appendSlice(alloc, tmp[0..n]);
            last_progress_ns = timer.read();
            continue;
        }

        const now = timer.read();
        if (now - last_progress_ns > stall_ns or now > total_ns) break;
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    return out.toOwnedSlice(alloc);
}

pub fn parseStatus(buf: []const u8) ?u16 {
    const lf = std.mem.indexOfScalar(u8, buf, '\n') orelse return null;
    const line_raw = buf[0..lf];
    const line = if (line_raw.len > 0 and line_raw[line_raw.len - 1] == '\r')
        line_raw[0 .. line_raw.len - 1]
    else
        line_raw;

    var it = std.mem.splitScalar(u8, line, ' ');
    _ = it.next() orelse return null;
    const code_s = it.next() orelse return null;
    return std.fmt.parseInt(u16, code_s, 10) catch null;
}

pub fn headerValue(headers_block: []const u8, name_ci: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, headers_block, '\n');
    while (it.next()) |line_cr| {
        var line = line_cr;
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

pub fn httpGet(
    A: std.mem.Allocator,
    port: u16,
    method: []const u8,
    path: []const u8,
    extra_headers: []const []const u8,
) !struct { status: u16, headers: []const u8, body: []const u8, raw: []u8 } {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    var s = try std.net.tcpConnectToAddress(addr);
    defer s.close();

    const req_line = try std.fmt.allocPrint(
        A,
        "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n",
        .{ method, path },
    );
    defer A.free(req_line);
    try writeAllStream(&s, req_line);

    for (extra_headers) |h| {
        try writeAllStream(&s, h);
    }
    try writeAllStream(&s, "\r\n");

    if (builtin.os.tag == .windows) {
        const ws2 = std.os.windows.ws2_32;
        _ = ws2.shutdown(s.handle, ws2.SD_SEND);
    } else {
        std.posix.shutdown(s.handle, .send) catch {};
    }

    const resp = try readAllToEnd(A, &s);

    const split = std.mem.indexOf(u8, resp, "\r\n\r\n") orelse return error.BadResponse;
    const hdrs = resp[0 .. split + 2];
    const st = parseStatus(resp) orelse return error.BadResponse;
    const body = resp[split + 4 ..];

    return .{ .status = st, .headers = hdrs, .body = body, .raw = resp };
}

pub fn startServer(A: std.mem.Allocator, port: u16) !std.Thread {
    const srv_ptr = try A.create(web.PreviewServer);
    errdefer A.destroy(srv_ptr);

    srv_ptr.* = try web.PreviewServer.init(A, ".");
    return try std.Thread.spawn(.{}, struct {
        fn run(srv: *web.PreviewServer, alloc: std.mem.Allocator, p: u16) void {
            defer { srv.deinit(); alloc.destroy(srv); }
            web.PreviewServer.listenAndServe(srv, p) catch {};
        }
    }.run, .{ srv_ptr, A, port });
}

pub fn stopServer(port: u16) void {
    // Best-effort shutdown via /__docz_stop. Treat "already down" as success.
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);

    var s = std.net.tcpConnectToAddress(addr) catch |e| {
        // Only handle errors that can reasonably mean "not listening yet/anymore"
        switch (e) {
            error.ConnectionRefused,
            error.ConnectionTimedOut,
            error.NetworkUnreachable,
            error.AddressNotAvailable,
            => return,
            else => return,
        }
    };
    defer s.close();

    const req = "GET /__docz_stop HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n";
    _ = writeAllStream(&s, req) catch {};

    if (builtin.os.tag == .windows) {
        const ws2 = std.os.windows.ws2_32;
        _ = ws2.shutdown(s.handle, ws2.SD_SEND);
    } else {
        _ = std.posix.shutdown(s.handle, .send) catch {};
    }
}

pub fn findFreePort() !u16 {
    var p: u32 = 49152;
    while (p <= 65535) : (p += 1) {
        const try_port: u16 = @intCast(p);
        const addr_try = std.net.Address.parseIp4("127.0.0.1", try_port) catch continue;
        const listener = std.net.Address.listen(addr_try, .{ .reuse_address = true }) catch {
            continue;
        };
        listener.deinit();
        return try_port;
    }
    return error.AddressInUse;
}

pub fn waitForPort(port: u16, timeout_ms: u64) !void {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    const start = std.time.milliTimestamp();
    while (true) {
        if (std.time.milliTimestamp() - start > timeout_ms) return error.TimedOut;
        const ok = std.net.tcpConnectToAddress(addr) catch |e| switch (e) {
            error.ConnectionRefused,
            error.ConnectionTimedOut,
            error.NetworkUnreachable,
            error.AddressNotAvailable,
            => false,
            else => false,
        };
        if (ok) |sock| {
            sock.close();
            return;
        }
        std.Thread.sleep(25 * std.time.ns_per_ms);
    }
}
