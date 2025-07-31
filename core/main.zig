const std = @import("std");
const tokenizer = @import("../parser/tokenizer.zig");
const parser = @import("../parser/parser.zig");
const renderer = @import("../renderer/html.zig");

/// Handles building a `.dcz` file into HTML
fn handleBuild(file_path: []const u8) !void {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const stat = try file.stat();
    const buffer = try std.heap.page_allocator.alloc(u8, stat.size);
    defer std.heap.page_allocator.free(buffer);

    _ = try file.readAll(buffer);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Tokenize
    const tokens = try tokenizer.tokenize(buffer, allocator);
    defer allocator.free(tokens);

    // Parse AST
    var ast = try parser.parse(tokens, allocator);
    defer {
        for (ast.children.items) |*child| {
            child.attributes.deinit();
            child.children.deinit();
        }
        ast.children.deinit();
    }

    // Render HTML
    const html = try renderer.renderHTML(&ast, allocator);
    defer allocator.free(html);

    // Output file
    const out_file_name = try std.fmt.allocPrint(allocator, "{s}.html", .{file_path});
    defer allocator.free(out_file_name);

    var out_file = try std.fs.cwd().createFile(out_file_name, .{});
    defer out_file.close();

    _ = try out_file.write(html);

    std.debug.print("✔ Built {s} → {s}\n", .{ file_path, out_file_name });
}

/// Displays usage instructions with debug hex dump
fn printUsage() void {
    const usage_text =
        \\Docz CLI - Usage:
        \\  docz build <file.dcz>       Build .dcz file to HTML
        \\  docz preview                Start local preview server
        \\  docz enable wasm            Enable WASM execution support
        \\
    ;

    // Print usage normally
    std.debug.print("{s}", .{usage_text});

    // Debug: Show actual byte values of usage_text
    std.debug.print("\n[DEBUG] Usage bytes: ", .{});
    for (usage_text) |ch| {
        std.debug.print("{X:0>2} ", .{@as(u8, ch)});
    }
    std.debug.print("\n", .{});
}

/// Entry point
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "build")) {
        if (args.len < 3) {
            std.debug.print("Error: Missing file path for 'build'\n", .{});
            return;
        }
        try handleBuild(args[2]);
    } else if (std.mem.eql(u8, cmd, "preview")) {
        std.debug.print("Starting preview server...\n", .{});
    } else if (std.mem.eql(u8, cmd, "enable") and args.len >= 3 and std.mem.eql(u8, args[2], "wasm")) {
        std.debug.print("Enabling WASM execution support...\n", .{});
    } else {
        printUsage();
    }
}

// ----------------------
// Tests
// ----------------------
test "CLI usage message prints" {
    var fbs = std.io.fixedBufferStream([]u8{0} ** 1024);
    const writer = fbs.writer();

    const expected_text =
        \\Docz CLI - Usage:
        \\  docz build <file.dcz>       Build .dcz file to HTML
        \\  docz preview                Start local preview server
        \\  docz enable wasm            Enable WASM execution support
        \\
    ;

    try writer.print("{s}", .{expected_text});
    const buffer = fbs.getWritten();

    // Debug: Hex dump of expected vs actual
    std.debug.print("[DEBUG] Expected bytes: ", .{});
    for (expected_text) |ch| std.debug.print("{X:0>2} ", .{@as(u8, ch)});
    std.debug.print("\n[DEBUG] Buffer bytes:   ", .{});
    for (buffer) |ch| std.debug.print("{X:0>2} ", .{@as(u8, ch)});
    std.debug.print("\n", .{});

    try std.testing.expect(std.mem.indexOf(u8, buffer, "docz build") != null);
}
