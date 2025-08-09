const std = @import("std");

/// A lightweight Server-Sent Events (SSE) utility + broadcaster
/// used by the web-preview server to push hot-reload notifications.
///
/// Usage sketch:
///   var bc = Broadcaster.init(allocator);
///   defer bc.deinit();
///   const id = try bc.add(my_sink); // where my_sink implements `Sink`
///   try bc.broadcast("reload", "examples/minimal.dcz");
///   _ = bc.remove(id);
/// A write target for SSE payloads (e.g., an HTTP response writer).
/// Implementors provide a `writeFn` that accepts the raw SSE bytes.
/// If `writeFn` errors, the broadcaster will drop that sink.
pub const Sink = struct {
    ctx: *anyopaque,
    writeFn: *const fn (ctx: *anyopaque, bytes: []const u8) anyerror!void,
};

/// Build a valid SSE event payload. Splits `data` by lines and prefixes
/// each with `data: `. Includes an `event:` line when `event` is non-empty.
/// Returns an owned buffer; caller must free.
pub fn formatSseEvent(allocator: std.mem.Allocator, event: []const u8, data: []const u8) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    const w = buf.writer();

    if (event.len != 0) {
        try w.print("event: {s}\n", .{event});
    }

    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        try w.print("data: {s}\n", .{line});
    }

    // SSE event terminator: exactly one blank line
    try w.writeAll("\n");

    // 👇 unwrap the error union
    var out: []u8 = try buf.toOwnedSlice();

    // Normalize: ensure exactly one trailing '\n'
    var n = out.len;
    var tail: usize = 0;
    while (n > 0 and out[n - 1] == '\n') : (n -= 1) {
        tail += 1;
    }
    if (tail > 1) {
        out = try allocator.realloc(out, out.len - (tail - 1));
    }

    return out;
}

/// Broadcasts events to a dynamic set of sinks. On write error,
/// the failing sink is removed.
pub const Broadcaster = struct {
    const Client = struct {
        id: u64,
        sink: Sink,
    };

    allocator: std.mem.Allocator,
    clients: std.ArrayList(Client),
    next_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) Broadcaster {
        return .{
            .allocator = allocator,
            .clients = std.ArrayList(Client).init(allocator),
            .next_id = 1,
        };
    }

    pub fn deinit(self: *Broadcaster) void {
        self.clients.deinit();
    }

    /// Add a sink; returns a unique client id.
    pub fn add(self: *Broadcaster, sink: Sink) !u64 {
        const id = self.next_id;
        self.next_id += 1;
        try self.clients.append(.{ .id = id, .sink = sink });
        return id;
    }

    /// Remove a sink by id; returns true if it existed.
    pub fn remove(self: *Broadcaster, id: u64) bool {
        var i: usize = 0;
        while (i < self.clients.items.len) : (i += 1) {
            if (self.clients.items[i].id == id) {
                _ = self.clients.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Send one SSE event to all active sinks. Any sink that errors is pruned.
    pub fn broadcast(self: *Broadcaster, event: []const u8, data: []const u8) !void {
        const payload = try formatSseEvent(self.allocator, event, data);
        defer self.allocator.free(payload);

        var i: usize = 0;
        while (i < self.clients.items.len) {
            const sink = self.clients.items[i].sink;

            // Attempt write; if it errors, drop this client and DON'T advance i.
            sink.writeFn(sink.ctx, payload) catch {
                _ = self.clients.orderedRemove(i);
                continue;
            };

            // Success: advance
            i += 1;
        }
    }
};

///////////////////////
//        Tests      //
///////////////////////

test "formatSseEvent: with event and multi-line data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try formatSseEvent(A, "reload", "a\nb\n");
    defer A.free(out);

    const expected =
        \\event: reload
        \\data: a
        \\data: b
        \\data: 
        \\
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "formatSseEvent: data only (no event line)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try formatSseEvent(A, "", "hello");
    defer A.free(out);

    const expected =
        \\data: hello
        \\
    ;
    try std.testing.expectEqualStrings(expected, out);
}

const TestBuffer = struct {
    list: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator) TestBuffer {
        return .{ .list = std.ArrayList(u8).init(allocator) };
    }
    fn deinit(self: *TestBuffer) void {
        self.list.deinit();
    }

    fn sink(self: *TestBuffer) Sink {
        return .{
            .ctx = self,
            .writeFn = write,
        };
    }

    fn write(ctx: *anyopaque, bytes: []const u8) !void {
        var self: *TestBuffer = @ptrCast(@alignCast(ctx));
        try self.list.appendSlice(bytes);
    }
};

test "Broadcaster: add, broadcast to two sinks, remove" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var bc = Broadcaster.init(A);
    defer bc.deinit();

    var buf1 = TestBuffer.init(A);
    defer buf1.deinit();
    var buf2 = TestBuffer.init(A);
    defer buf2.deinit();

    const id1 = try bc.add(buf1.sink());
    const id2 = try bc.add(buf2.sink());

    try bc.broadcast("ping", "X");

    const expected =
        \\event: ping
        \\data: X
        \\
    ;

    try std.testing.expectEqualStrings(expected, buf1.list.items);
    try std.testing.expectEqualStrings(expected, buf2.list.items);

    try std.testing.expect(bc.remove(id1));
    try std.testing.expect(bc.remove(id2));
    try std.testing.expect(!bc.remove(9999));
}

test "Broadcaster: auto-prunes a failing sink" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var bc = Broadcaster.init(A);
    defer bc.deinit();

    // good sink
    var good = TestBuffer.init(A);
    defer good.deinit();
    _ = try bc.add(good.sink());

    // bad sink that always errors
    const Bad = struct {
        fn make() Sink {
            return .{ .ctx = undefined, .writeFn = fail };
        }
        fn fail(_: *anyopaque, _: []const u8) !void {
            return error.Disconnected;
        }
    };
    _ = try bc.add(Bad.make());

    try bc.broadcast("tick", "ok");
    // After broadcast, the bad sink should have been removed; a second broadcast still succeeds.
    try bc.broadcast("tock", "ok");

    const expected_first =
        \\event: tick
        \\data: ok
        \\
    ;
    const expected_second =
        \\event: tock
        \\data: ok
        \\
    ;
    // good buffer should have both concatenated writes
    try std.testing.expect(std.mem.indexOf(u8, good.list.items, expected_first) != null);
    try std.testing.expect(std.mem.indexOf(u8, good.list.items, expected_second) != null);
}
