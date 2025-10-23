const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    // Keep it dead simple and compatible with your snapshot: use std.debug.print.
    std.debug.print("Docz build info\n", .{});
    std.debug.print("  Zig:      {d}.{d}.{d}\n", .{
        builtin.zig_version.major,
        builtin.zig_version.minor,
        builtin.zig_version.patch,
    });
    std.debug.print("  Target:   {s}-{s}-{s}\n", .{
        @tagName(builtin.cpu.arch),
        @tagName(builtin.os.tag),
        @tagName(builtin.abi),
    });
    std.debug.print("  Optimize: {s}\n", .{@tagName(builtin.mode)});

    // If you later add build options (e.g., git commit), print them here:
    // const opts = @import("build_options");
    // std.debug.print("  Git:      {s}\n", .{ opts.git_commit });
}
