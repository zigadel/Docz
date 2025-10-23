const std = @import("std");
const server_mod = @import("web_preview");

// --- Tunables ---------------------------------------------------------------
const BOOT_WAIT_SLICE_MS: u64 = 25; // small retry step while server boots
const BOOT_BUDGET_MS: u64 = 6000; // give the server up to 6s to bind
const READ_WAIT_SLICE_MS: u64 = 25; // socket read backoff
const READ_BUDGET_MS: u64 = 4000; // how long we’re willing to wait for bytes
// ---------------------------------------------------------------------------

fn fileExists(path: []const u8) bool {
    _ = std.fs.cwd().statFile(path) catch return false;
    return true;
}

// tiny/forgiving scanner for:  "key" : "value"
fn findJsonStringValue(buf: []const u8, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        if (buf[i] != '"') continue;

        const start_key = i + 1;
        var j = start_key;
        while (j < buf.len and buf[j] != '"') : (j += 1) {}
        if (j >= buf.len) break;

        const kslice = buf[start_key..j];
        i = j + 1;

        // skip whitespace
        while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}

        // expect colon
        if (i >= buf.len) continue;
        if (buf[i] != ':') continue;
        i += 1;

        // skip whitespace
        while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
        if (i >= buf.len) break;

        // match "value"
        if (i < buf.len and buf[i] == '"' and std.mem.eql(u8, kslice, key)) {
            const vs = i + 1;
            var ve = vs;
            while (ve < buf.len and buf[ve] != '"') : (ve += 1) {}
            if (ve <= buf.len) return buf[vs..ve];
        }
    }
    return null;
}

/// Read up to `max_bytes` from a file into an allocator-backed slice.
fn readFilePrefixAlloc(a: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    const size = try f.getEndPos();
    const want: usize = if (size > max_bytes) max_bytes else @as(usize, @intCast(size));

    var buf = try a.alloc(u8, want);
    const n = try f.readAll(buf);
    return buf[0..n];
}

/// Find one “real” third_party asset path that the preview server should serve.
/// Returns an allocator-owned string that the caller must free.
fn findAnyThirdPartyAsset(a: std.mem.Allocator) !?[]const u8 {
    // Check lock file first for katex/tailwind versions
    if (fileExists("third_party.lock")) {
        const buf = try readFilePrefixAlloc(a, "third_party.lock", 64 * 1024);
        defer a.free(buf);

        if (findJsonStringValue(buf, "katex")) |ver| {
            const abs = try std.fs.path.join(a, &.{ "third_party", "katex", ver, "dist", "katex.min.css" });
            defer a.free(abs);
            if (fileExists(abs)) {
                return try std.fmt.allocPrint(a, "/third_party/katex/{s}/dist/katex.min.css", .{ver});
            }
        }
        if (findJsonStringValue(buf, "tailwind")) |label| {
            const abs = try std.fs.path.join(a, &.{ "third_party", "tailwind", label, "css", "docz.tailwind.css" });
            defer a.free(abs);
            if (fileExists(abs)) {
                return try std.fmt.allocPrint(a, "/third_party/tailwind/{s}/css/docz.tailwind.css", .{label});
            }
        }
    }

    // Fallback: scan directories directly (take the first match we can stat)
    if (std.fs.cwd().openDir("third_party/katex", .{ .iterate = true })) |dir_val| {
        var d = dir_val; // make it mutable so .close takes *Dir (not *const Dir)
        defer d.close();

        var it = d.iterate();
        while (true) {
            const n = it.next() catch break;
            if (n == null) break;
            const e = n.?;
            if (e.kind != .directory) continue;

            const abs = try std.fs.path.join(a, &.{ "third_party", "katex", e.name, "dist", "katex.min.css" });
            defer a.free(abs);
            if (fileExists(abs)) {
                return try std.fmt.allocPrint(a, "/third_party/katex/{s}/dist/katex.min.css", .{e.name});
            }
        }
    } else |_| {}

    if (std.fs.cwd().openDir("third_party/tailwind", .{ .iterate = true })) |dir_val2| {
        var d2 = dir_val2;
        defer d2.close();

        var it2 = d2.iterate();
        while (true) {
            const n = it2.next() catch break;
            if (n == null) break;
            const e = n.?;
            if (e.kind != .directory) continue;

            const abs = try std.fs.path.join(a, &.{ "third_party", "tailwind", e.name, "css", "docz.tailwind.css" });
            defer a.free(abs);
            if (fileExists(abs)) {
                return try std.fmt.allocPrint(a, "/third_party/tailwind/{s}/css/docz.tailwind.css", .{e.name});
            }
        }
    } else |_| {}

    return null;
}

fn nowMs() u64 {
    const t = std.time.milliTimestamp();
    return @as(u64, @intCast(if (t < 0) 0 else t));
}

fn sleepMs(ms: u64) void {
    std.Thread.sleep(ms * std.time.ns_per_ms);
}

/// Try connecting until the TCP listener is accepting (with a firm time budget).
fn waitUntilListening(a: std.mem.Allocator, host: []const u8, port: u16) !void {
    const deadline = nowMs() + BOOT_BUDGET_MS;
    while (true) {
        if (nowMs() >= deadline) return error.TimedOut;
        const s = std.net.tcpConnectToHost(a, host, port) catch |e| switch (e) {
            error.ConnectionRefused,
            error.HostLacksNetworkAddresses,
            error.NetworkUnreachable,
            error.NameServerFailure,
            error.TemporaryNameServerFailure,
            error.UnknownHostName,
            => {
                sleepMs(BOOT_WAIT_SLICE_MS);
                continue;
            },
            else => return e,
        };
        // If connect worked, the listener is up; close this probe socket and return.
        s.close();
        return;
    }
}

test "preview serves third_party assets" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    // Pick one asset we know should exist
    const maybe_asset = try findAnyThirdPartyAsset(A);
    if (maybe_asset == null) return error.SkipZigTest;
    const asset_path = maybe_asset.?; // e.g. /third_party/katex/<ver>/dist/katex.min.css
    defer A.free(asset_path);

    // Start the preview server
    var srv = try server_mod.PreviewServer.init(A, ".");
    defer srv.deinit();

    const port: u16 = 5179;
    _ = try std.Thread.spawn(.{}, server_mod.PreviewServer.listenAndServe, .{ &srv, port });

    // Actively wait for the TCP listener
    try waitUntilListening(A, "127.0.0.1", port);

    // Build URL/URI
    var client = std.http.Client{ .allocator = A };
    defer client.deinit();

    const url = try std.fmt.allocPrint(A, "http://127.0.0.1:{d}{s}", .{ port, asset_path });
    defer A.free(url);

    const uri = try std.Uri.parse(url);

    // Retry once or twice to smooth over Windows ReadFile(87)/RST on first connection
    var status: std.http.Status = .internal_server_error;
    var attempt: usize = 0;
    while (attempt < 3) : (attempt += 1) {
        var req = try client.request(.GET, uri, .{
            .headers = .{
                // Force a simple close-after-response behavior
                .connection = .{ .override = "close" },
            },
            // Also tell std.http to not try to keep the connection
            .keep_alive = false,
        });
        defer req.deinit();

        // Send a GET with no body; transient write errors -> retry
        const send_res = req.sendBodiless();
        if (send_res) |*_| {} else |e| switch (e) {
            error.WriteFailed => {
                std.Thread.sleep(150 * std.time.ns_per_ms);
                continue;
            },
            else => return e,
        }

        // Receive only the head; transient read errors -> retry
        var redirect_buf: [1024]u8 = undefined;
        const resp = req.receiveHead(&redirect_buf) catch |e| switch (e) {
            error.ReadFailed => {
                std.Thread.sleep(150 * std.time.ns_per_ms);
                continue;
            },
            error.WriteFailed => {
                std.Thread.sleep(150 * std.time.ns_per_ms);
                continue;
            },
            else => return e,
        };

        status = resp.head.status;
        // We don’t need the body; returning from test soon, so just break.
        break;
    }

    try std.testing.expect(status == .ok);
}
