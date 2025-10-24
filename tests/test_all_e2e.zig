const std = @import("std");

comptime {
    _ = @import("e2e/cli_usage.zig");
    _ = @import("e2e/file_to_html.zig");
    _ = @import("e2e/enable_wasm.zig");
    _ = @import("e2e/convert_cli.zig");
    // _ = @import("e2e/preview_cli_smoke.zig");
}

test {
    std.testing.refAllDecls(@This());
}
