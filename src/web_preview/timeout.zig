const std = @import("std");

/// A thin deadline-based reader wrapper. If now() passes deadline_ns, returns error.Timeout.
pub fn DeadlineReader(comptime T: type) type {
    return struct {
        inner: T,
        clock: *std.time.Timer,
        deadline_ns: u64,

        pub fn init(inner: T, clock: *std.time.Timer, ms: u32) @This() {
            return .{
                .inner = inner,
                .clock = clock,
                .deadline_ns = clock.read() + (std.time.ns_per_ms * @as(u64, ms)),
            };
        }

        pub fn read(self: *@This(), buf: []u8) !usize {
            if (self.clock.read() > self.deadline_ns) return error.Timeout;
            // Non-blocking deadline enforcement would need OS-specific polling;
            // we keep it simple: rely on short OS read and re-check deadline.
            const n = try self.inner.read(buf);
            if (self.clock.read() > self.deadline_ns) return error.Timeout;
            return n;
        }
    };
}
