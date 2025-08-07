const std = @import("std");

comptime {
    _ = @import("e2e/cli_usage.zig");
    _ = @import("e2e/file_to_html.zig");
}

test {
    std.testing.refAllDecls(@This());
}
