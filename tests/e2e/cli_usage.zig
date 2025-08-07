const std = @import("std");

test "CLI usage text contains 'docz build'" {
    const docz = @import("docz");
    const main = docz.main;
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const writer = stream.writer();

    try writer.print("{s}", .{main.USAGE_TEXT});
    const output = stream.getWritten();

    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "docz build"));
}
