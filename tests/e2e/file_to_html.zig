const std = @import("std");
const docz = @import("docz");
const tokenizer = docz.parser.tokenizer;
const parser = docz.parser.parser;
const renderer = docz.renderer.html;

test "📄 Parse and render a basic .dcz file to HTML" {
    const input =
        \\@meta(title="Hello")
        \\@heading(level=1) Welcome to Docz @end
        \\@code(language="zig")
        \\const x = 42;
        \\@end
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const tokens = try tokenizer.tokenize(input, allocator);
    defer {
        docz.Tokenizer.freeTokens(allocator, tokens);
        allocator.free(tokens);
    }

    var ast = try parser.parse(tokens, allocator);
    defer ast.deinit(allocator);

    const html = try renderer.renderHTML(&ast, allocator);
    defer allocator.free(html);

    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h1>Welcome to Docz</h1>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "const x = 42;"));
}
