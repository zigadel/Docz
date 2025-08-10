const std = @import("std");

comptime {
    _ = @import("integration/tokenizer.zig");
    _ = @import("integration/parser.zig");
    _ = @import("integration/renderer.zig");
    _ = @import("integration/pipeline.zig");
    _ = @import("integration/convert_html_import.zig");
}

test {
    std.testing.refAllDecls(@This());
}
