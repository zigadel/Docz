const std = @import("std");
const tokenizer = @import("parser/tokenizer.zig");
const parser = @import("parser/parser.zig");
const renderer = @import("renderer/html.zig");

/// Global constant for CLI usage text
pub const USAGE_TEXT =
    \\Docz CLI Usage:
    \\  docz build <file.dcz>       Build .dcz file to HTML
    \\  docz preview                Start local preview server
    \\  docz enable wasm            Enable WASM execution support
    \\
;

/// CLI entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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
        // TODO: HTTP server
    } else if (std.mem.eql(u8, cmd, "enable") and args.len >= 3 and std.mem.eql(u8, args[2], "wasm")) {
        std.debug.print("Enabling WASM execution support...\n", .{});
        // TODO: WASM logic
    } else {
        printUsage();
    }
}

/// Prints usage help text
fn printUsage() void {
    std.debug.print("{s}", .{USAGE_TEXT});
}

/// Handles the `docz build file.dcz` command
fn handleBuild(file_path: []const u8) !void {
    // Open input file
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const stat = try file.stat();
    const buffer = try std.heap.page_allocator.alloc(u8, stat.size);
    defer std.heap.page_allocator.free(buffer);

    _ = try file.readAll(buffer);

    // Tokenize
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const tokens = try tokenizer.tokenize(buffer, allocator);
    defer allocator.free(tokens);

    // Parse
    var ast = try parser.parse(tokens, allocator);
    defer {
        for (ast.children.items) |*child| {
            child.attributes.deinit();
            child.children.deinit();
        }
        ast.children.deinit();
    }

    // Render
    const html = try renderer.renderHTML(&ast, allocator);
    defer allocator.free(html);

    // Output
    const out_file_name = try std.fmt.allocPrint(allocator, "{s}.html", .{file_path});
    defer allocator.free(out_file_name);

    var out_file = try std.fs.cwd().createFile(out_file_name, .{});
    defer out_file.close();

    _ = try out_file.write(html);

    std.debug.print("✔ Built {s} → {s}\n", .{ file_path, out_file_name });
}

// Simple test for CLI usage message
test "CLI usage message prints" {
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    try writer.print("{s}", .{USAGE_TEXT});

    const written = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "docz build") != null);
}
