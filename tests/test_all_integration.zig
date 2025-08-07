const std = @import("std");

comptime {
    _ = @import("integration/tokenizer.zig");
    _ = @import("integration/parser.zig");
    _ = @import("integration/renderer.zig");
    _ = @import("integration/pipeline.zig");
}

test {
    std.testing.refAllDecls(@This());
}
