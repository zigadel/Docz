const std = @import("std");
const tokenizer = @import("../parser/tokenizer.zig");

const parser = @import("../parser/parser.zig");

const renderer = @import("../renderer/html.zig");

fn handleBuild(file_path: []const u8) !void {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const stat = try file.stat();
    const buffer = try std.heap.page_allocator.alloc(u8, stat.size);
    defer std.heap.page_allocator.free(buffer);

    _ = try file.readAll(buffer);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = gpa.allocator();

    const tokens = try tokenizer.tokenize(buffer, allocator);
    defer allocator.free(tokens);

    const ast = try parser.parse(tokens, allocator);

    const html = try renderer.renderHTML(&ast, allocator);
    defer allocator.free(html);

    const out_file_name = try std.fmt.allocPrint(allocator, "{s}.html", .{file_path});
    defer allocator.free(out_file_name);

    var out_file = try std.fs.cwd().createFile(out_file_name, .{});
    defer out_file.close();

    _ = try out_file.write(html);

    std.debug.print("✔ Built {s} → {s}\n", .{ file_path, out_file_name });
}
