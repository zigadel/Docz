const std = @import("std");
const server_mod = @import("docz").web_preview.server;

// ---------- tiny helpers ----------

fn fileExists(path: []const u8) bool {
    _ = std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn tryReadFileAlloc(A: std.mem.Allocator, path: []const u8, max: usize) ?[]u8 {
    var f = std.fs.cwd().openFile(path, .{}) catch return null;
    defer f.close();
    return f.readToEndAlloc(A, max) catch null;
}

/// Very small JSON key lookup: {"key":"value"} -> returns unquoted slice.
/// (No escapes needed for our simple version/label strings.)
fn findJsonStringValue(buf: []const u8, key: []const u8) ?[]const u8 {
    var pat_buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&pat_buf);
    const A = fba.allocator();
    const quoted_key = std.fmt.allocPrint(A, "\"{s}\"", .{key}) catch return null;

    const key_i = std.mem.indexOf(u8, buf, quoted_key) orelse return null;

    var i: usize = key_i + quoted_key.len;
    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    if (i >= buf.len or buf[i] != ':') return null;
    i += 1;

    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    if (i >= buf.len or buf[i] != '"') return null;
    i += 1;

    const start = i;
    while (i < buf.len and buf[i] != '"') : (i += 1) {}
    if (i >= buf.len) return null;

    return buf[start..i];
}

/// Try to find a vendored asset to request:
/// 1) Prefer VENDOR.lock (katex/tailwind versions), verify file exists
/// 2) Fallback: scan third_party trees for known files
/// Returns an HTTP path like "/third_party/...".
fn findAnyThirdPartyAsset(A: std.mem.Allocator) !?[]const u8 {
    // 1) VENDOR.lock
    if (tryReadFileAlloc(A, "third_party/VENDOR.lock", 1 << 16)) |lock_buf| {
        defer A.free(lock_buf);

        if (findJsonStringValue(lock_buf, "katex")) |ver| {
            const abs = try std.fs.path.join(A, &.{ "third_party", "katex", ver, "dist", "katex.min.css" });
            defer A.free(abs);
            if (fileExists(abs)) {
                return try std.fmt.allocPrint(A, "/third_party/katex/{s}/dist/katex.min.css", .{ver});
            }
        }
        if (findJsonStringValue(lock_buf, "tailwind")) |label| {
            const abs = try std.fs.path.join(A, &.{ "third_party", "tailwind", label, "css", "docz.tailwind.css" });
            defer A.free(abs);
            if (fileExists(abs)) {
                return try std.fmt.allocPrint(A, "/third_party/tailwind/{s}/css/docz.tailwind.css", .{label});
            }
        }
    }

    // 2) Fallback scan (KaTeX)
    if (std.fs.cwd().openDir("third_party/katex", .{ .iterate = true })) |d| {
        var dir = d; // make mutable so .close() can take *Dir
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |e| {
            if (e.kind != .directory) continue;
            if (e.name.len == 0 or e.name[0] == '.') continue;

            const abs = try std.fs.path.join(A, &.{ "third_party", "katex", e.name, "dist", "katex.min.css" });
            defer A.free(abs);
            if (fileExists(abs)) {
                return try std.fmt.allocPrint(A, "/third_party/katex/{s}/dist/katex.min.css", .{e.name});
            }
        }
    } else |_| {}

    // 3) Fallback scan (Tailwind)
    if (std.fs.cwd().openDir("third_party/tailwind", .{ .iterate = true })) |d| {
        var dir = d; // make mutable so .close() can take *Dir
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |e| {
            if (e.kind != .directory) continue;
            if (e.name.len == 0 or e.name[0] == '.') continue;

            const abs = try std.fs.path.join(A, &.{ "third_party", "tailwind", e.name, "css", "docz.tailwind.css" });
            defer A.free(abs);
            if (fileExists(abs)) {
                return try std.fmt.allocPrint(A, "/third_party/tailwind/{s}/css/docz.tailwind.css", .{e.name});
            }
        }
    } else |_| {}

    return null; // nothing vendored yet
}

// ---------- test ----------

test "preview serves third_party assets" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const maybe_asset = try findAnyThirdPartyAsset(A);
    if (maybe_asset == null) return error.SkipZigTest; // skip cleanly when repo has no assets yet

    var srv = try server_mod.PreviewServer.init(A, ".");
    defer srv.deinit();

    const port: u16 = 5179;
    _ = try std.Thread.spawn(.{}, server_mod.PreviewServer.listenAndServe, .{ &srv, port });

    // Give the server a moment to bind
    std.Thread.sleep(200 * std.time.ns_per_ms);

    // TCP GET to the preview server
    var stream = try std.net.tcpConnectToHost(A, "127.0.0.1", port);
    defer stream.close();

    const path = maybe_asset.?;
    defer A.free(path);

    var req_buf = std.ArrayList(u8).init(A);
    defer req_buf.deinit();
    try req_buf.writer().print(
        "GET {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
        .{path},
    );

    // write-all
    var to_write = req_buf.items;
    while (to_write.len > 0) {
        const n = try stream.write(to_write);
        to_write = to_write[n..];
    }

    // read-all (EOF => n == 0)
    var resp = std.ArrayList(u8).init(A);
    defer resp.deinit();

    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = try stream.read(&tmp);
        if (n == 0) break;
        try resp.appendSlice(tmp[0..n]);
    }

    // Expect 200 OK when an asset exists
    try std.testing.expect(std.mem.startsWith(u8, resp.items, "HTTP/1.1 200"));
}
