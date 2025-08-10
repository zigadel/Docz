const std = @import("std");

// Thin CLI dispatcher: each subcommand lives in src/cli/*.zig
const cli_convert = @import("cli/convert.zig");
const cli_build_cmd = @import("cli/build_cmd.zig");
const cli_preview = @import("cli/preview.zig");
const cli_enable = @import("cli/enable_wasm.zig");

/// Global constant for CLI usage text (keeps original lines; adds convert/export)
pub const USAGE_TEXT =
    \\Docz CLI Usage:
    \\  docz build <file.dcz>       Build .dcz file to HTML
    \\  docz preview                Start local preview server
    \\  docz enable wasm            Enable WASM execution support
    \\  docz convert <input.{dcz|md|html|htm|tex}> [--to|-t <output.{dcz|md|html|tex}>]
    \\  docz export  <input.{dcz|md|html|htm|tex}> [--to|-t <output.{dcz|md|html|tex}>]
    \\
;

/// CLI entry point: parse args → dispatch to subcommand module.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var it = try std.process.argsWithAllocator(A);
    defer it.deinit();

    _ = it.next(); // program name
    const cmd = it.next() orelse {
        printUsage();
        return;
    };

    // Dispatch table
    if (std.mem.eql(u8, cmd, "build")) {
        try cli_build_cmd.run(A, &it);
        return;
    }
    if (std.mem.eql(u8, cmd, "preview")) {
        try cli_preview.run(A, &it);
        return;
    }
    if (std.mem.eql(u8, cmd, "enable")) {
        // enable_wasm expects the next token to be "wasm"
        try cli_enable.run(A, &it);
        return;
    }
    if (std.mem.eql(u8, cmd, "convert") or std.mem.eql(u8, cmd, "export")) {
        try cli_convert.run(A, &it);
        return;
    }

    printUsage();
}

/// Prints usage help text (no std.io handles → portable across nightlies)
fn printUsage() void {
    // std.debug.print writes to stderr on most toolchains; that’s fine for usage/help.
    std.debug.print("{s}", .{USAGE_TEXT});
}

// Simple test for CLI usage message
test "CLI usage message prints" {
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    try writer.writeAll(USAGE_TEXT);

    const written = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "docz build") != null);
}
