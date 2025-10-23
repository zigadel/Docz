const std = @import("std");
const core = @import("vendor_core.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    // Verify only (no HTTP compiled)
    try core.verifyAll(A);
}
