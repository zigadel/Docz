const std = @import("std");
const limits_mod = @import("../../src/web_preview/limits.zig"); // keep your current layout

test "limits: contentLengthFrom parses integers and ignores junk" {
    const good =
        \\Content-Length: 123\r
        \\X: y\r
        \\ \r
        \\
    ;
    try std.testing.expectEqual(@as(usize, 123), limits_mod.contentLengthFrom(good));

    const bad =
        \\Content-Length: nope\r
        \\ \r
        \\
    ;
    try std.testing.expectEqual(@as(usize, 0), limits_mod.contentLengthFrom(bad));
}
