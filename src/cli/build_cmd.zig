const std = @import("std");
const docz = @import("docz"); // exposes Tokenizer, Parser, Renderer (HTML)
const html_export = @import("html_export");

pub fn run(A: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const in_path = it.next() orelse {
        std.debug.print("Usage: docz build <file.dcz>\n", .{});
        return error.Invalid;
    };

    // 1) Read input
    const input = try readFileAlloc(A, in_path);
    defer A.free(input);

    // 2) DCZ -> tokens -> AST
    const tokens = try docz.Tokenizer.tokenize(input, A);
    defer {
        docz.Tokenizer.freeTokens(A, tokens);
        A.free(tokens);
    }

    var ast = try docz.Parser.parse(tokens, A);
    defer ast.deinit(A);

    // 3) Render HTML
    const html = try html_export.exportHtml(&ast, A);
    defer A.free(html);

    // 4) Write <in>.html
    const out_path = try std.fmt.allocPrint(A, "{s}.html", .{in_path});
    defer A.free(out_path);

    try writeFile(out_path, html);

    // 5) Match existing CLI message shape
    std.debug.print("✔ Built {s} → {s}\n", .{ in_path, out_path });
}

fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    // order: (path, alloc, std.Io.Limit)
    return std.fs.cwd().readFileAlloc(path, alloc, @enumFromInt(1 << 26));
}

fn writeFile(path: []const u8, data: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}
