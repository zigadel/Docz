const std = @import("std");

pub const VERBOSE = @import("build_options").verbose_tests;

pub inline fn vprint(comptime fmt: []const u8, args: anytype) void {
    if (!VERBOSE) return;
    std.debug.print(fmt, args);
}
