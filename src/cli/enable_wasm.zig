const std = @import("std");

/// `docz enable wasm`
pub fn run(_: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    // Expect exactly one arg: "wasm"
    const sub = it.next() orelse {
        std.debug.print("Usage: docz enable wasm\n", .{});
        return error.Invalid;
    };

    if (!std.mem.eql(u8, sub, "wasm")) {
        std.debug.print("Usage: docz enable wasm\n", .{});
        return error.Invalid;
    }

    // Do whatever enabling would mean later; for now just a friendly confirmation.
    std.debug.print("Enabling WASM execution support...\n", .{});
}
