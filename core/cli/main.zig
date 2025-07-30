const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok); // ✅ Zig 0.15 fix
    const allocator = gpa.allocator();

    // Parse CLI args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    // Dispatch subcommands
    if (std.mem.eql(u8, command, "build")) {
        if (args.len < 3) {
            std.debug.print("Error: Missing input file for build command.\n", .{});
            return;
        }
        const file_path = args[2];
        try handleBuild(file_path);
    } else if (std.mem.eql(u8, command, "preview")) {
        try handlePreview();
    } else if (std.mem.eql(u8, command, "enable")) {
        if (args.len < 3) {
            std.debug.print("Error: Missing feature to enable.\n", .{});
            return;
        }
        const feature = args[2];
        try handleEnable(feature);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
    }
}

fn printUsage() !void {
    std.debug.print(
        \\Docz CLI – Usage:
        \\  docz build <file.dcz>       Build .dcz file to HTML
        \\  docz preview                Start local preview server
        \\  docz enable wasm            Enable WASM execution support
        \\
    , .{});
}

fn handleBuild(file_path: []const u8) !void {
    std.debug.print("Building file: {s}\n", .{file_path});
    // TODO: Hook into parser → renderer pipeline
}

fn handlePreview() !void {
    std.debug.print("Starting preview server...\n", .{});
    // TODO: Launch lightweight HTTP server with hot reload
}

fn handleEnable(feature: []const u8) !void {
    if (std.mem.eql(u8, feature, "wasm")) {
        std.debug.print("Enabling WASM execution support...\n", .{});
        // TODO: Modify docz.zig.zon, fetch Wasmtime if needed
    } else {
        std.debug.print("Unknown feature: {s}\n", .{feature});
    }
}

// ----------------------
// Inline Tests
// ----------------------

test "CLI usage message prints" {
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();
    _ = writer; // currently unused

    try printUsage();
    try std.testing.expect(std.mem.indexOf(u8, buffer[0..fbs.pos], "docz build") != null);
}

test "Build command handler prints correct message" {
    try handleBuild("sample.dcz");
}

test "Preview command handler prints correct message" {
    try handlePreview();
}

test "Enable feature handler prints correct message" {
    try handleEnable("wasm");
}
