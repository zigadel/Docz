const std = @import("std");
const builtin = @import("builtin");
const web = @import("web_preview");
const tnet = @import("test_net");

// ─────────────────────────────────────────────────────────────────────────────
// third_party assets: long immutable caching
// ─────────────────────────────────────────────────────────────────────────────

test "third_party assets get long immutable caching" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const port: u16 = try web.findFreePort();
    var th = try tnet.startServer(A, port);
    defer th.join();

    try web.waitForPort(port, 1000);

    const path = "/third_party/katex/0.16.22/dist/katex.min.css";
    const r = try tnet.httpGet(A, port, "GET", path, &.{});
    defer A.free(r.raw);

    try std.testing.expectEqual(@as(u16, 200), r.status);
    const cc = tnet.headerValue(r.headers, "Cache-Control") orelse return error.MissingHeader;
    try std.testing.expect(std.mem.indexOf(u8, cc, "immutable") != null);

    tnet.stopServer(port);
}

// ─────────────────────────────────────────────────────────────────────────────
// ETag -> 304 roundtrip for third_party asset
// ─────────────────────────────────────────────────────────────────────────────

test "ETag + 304 roundtrip for third_party asset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const port = try web.findFreePort();
    var th = try tnet.startServer(A, port);
    defer th.join();

    try web.waitForPort(port, 1000);

    const path = "/third_party/katex/0.16.22/dist/katex.min.css";
    const r1 = try tnet.httpGet(A, port, "GET", path, &.{});
    defer A.free(r1.raw);

    const etag = tnet.headerValue(r1.headers, "ETag") orelse return error.MissingHeader;

    var etag_hdr_buf: [256]u8 = undefined;
    // NOTE: include trailing CRLF; tnet.httpGet expects each extra header to be a full line.
    const etag_hdr = try std.fmt.bufPrint(&etag_hdr_buf, "If-None-Match: {s}\r\n", .{etag});

    const r2 = try tnet.httpGet(A, port, "GET", path, &.{etag_hdr});
    defer A.free(r2.raw);

    try std.testing.expectEqual(@as(u16, 304), r2.status);

    tnet.stopServer(port);
}

// ─────────────────────────────────────────────────────────────────────────────
// Single Range → 206 (skip on Windows until std.http.Client refactor)
// ─────────────────────────────────────────────────────────────────────────────

test "single Range request returns 206 and correct Content-Range" {
    if (builtin.os.tag == .windows) return; // un-skip later when we switch to std.http.Client

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const port: u16 = try web.findFreePort();
    var th = try tnet.startServer(A, port);
    defer th.join();

    try web.waitForPort(port, 1000);

    const path = "/third_party/katex/0.16.22/dist/katex.min.css";
    const r_full = try tnet.httpGet(A, port, "GET", path, &.{});
    defer A.free(r_full.raw);

    const r_hdr = "Range: bytes=0-9\r\n";
    const r_part = try tnet.httpGet(A, port, "GET", path, &.{r_hdr});
    defer A.free(r_part.raw);

    try std.testing.expectEqual(@as(u16, 206), r_part.status);
    const cr = tnet.headerValue(r_part.headers, "Content-Range") orelse return error.MissingHeader;
    try std.testing.expect(std.mem.startsWith(u8, cr, "bytes 0-9/"));
    try std.testing.expectEqual(@as(usize, 10), r_part.body.len);

    tnet.stopServer(port);
}

// ─────────────────────────────────────────────────────────────────────────────
// HEAD behavior: no body, Content-Length present
// ─────────────────────────────────────────────────────────────────────────────

test "HEAD on /ping suppresses body but reports length" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const port: u16 = try web.findFreePort();

    var th = try tnet.startServer(A, port);
    defer th.join();

    try web.waitForPort(port, 1000);

    const r = try tnet.httpGet(A, port, "HEAD", "/ping", &.{});
    defer A.free(r.raw);

    try std.testing.expectEqual(@as(u16, 200), r.status);

    const cl = tnet.headerValue(r.headers, "Content-Length") orelse return error.MissingHeader;
    try std.testing.expectEqual(@as(usize, 0), r.body.len);
    _ = std.fmt.parseInt(usize, cl, 10) catch return error.BadLength;

    tnet.stopServer(port);
}
