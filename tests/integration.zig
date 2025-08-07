const std = @import("std");
const docz = @import("docz");

test "Full pipeline integration: .dcz input → HTML output" {
    const input_docz =
        \\@meta(title="Integration Test", author="Docz Team") @end
        \\@heading(level=2) Hello, Docz! @end
        \\@code(language="zig")
        \\const x = 123;
        \\@end
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Tokenize
    const tokens = try docz.Tokenizer.tokenize(input_docz, allocator);
    defer allocator.free(tokens);

    // Parse to AST
    var ast = try docz.Parser.parse(tokens, allocator);
    defer ast.deinit();

    // Render to HTML
    const html = try docz.Renderer.renderHTML(&ast, allocator);
    defer allocator.free(html);

    // Assert key substrings exist in rendered HTML
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h2>Hello, Docz!</h2>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "const x = 123;"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "Integration Test"));
}
