const std = @import("std");

test "Run all end-to-end tests" {
    // Import e2e test files explicitly
    _ = @import("e2e/file_to_html.zig");
    _ = @import("e2e/cli_usage.zig");
    // Add more as needed
}
