const std = @import("std");
const docz = @import("docz");

test "🔧 Enable WASM Command Listed in Usage" {
    const usage = docz.main.USAGE_TEXT;

    std.debug.print("\n🔍 Verifying 'enable wasm' appears in help output...\n", .{});
    try std.testing.expect(std.mem.containsAtLeast(u8, usage, 1, "enable wasm"));
}
