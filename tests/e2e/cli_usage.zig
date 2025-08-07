const std = @import("std");
const docz = @import("docz");

test "🧪 CLI Usage Text Contains 'docz build'" {
    const usage = docz.main.USAGE_TEXT;

    std.debug.print("\n📋 CLI USAGE TEXT:\n{s}\n", .{usage});
    try std.testing.expect(std.mem.containsAtLeast(u8, usage, 1, "docz build"));
    try std.testing.expect(std.mem.containsAtLeast(u8, usage, 1, "docz preview"));
}
