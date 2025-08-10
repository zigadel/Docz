const std = @import("std");

// Minimal stub to keep behavior identical to your current CLI.
// We’ll replace this with the real web-preview server when ready.
pub fn run(_: std.mem.Allocator, _: *std.process.ArgIterator) !void {
    std.debug.print("Starting preview server...\n", .{});
    // TODO: start HTTP server (src/web-preview/*)
}
