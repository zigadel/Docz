const std = @import("std");
const docz = @import("docz");

pub const _force_test_discovery = true;

test "integration: renderer produces HTML from simple AST" {
    const input =
        \\@heading(level=3) Render Test @end
        \\Code below:
        \\@code(language="zig")
        \\const x = 9;
        \\@end
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Tokenize
    const tokens = try docz.Tokenizer.tokenize(input, allocator);
    // IMPORTANT: since we'll parse, the AST owns any lexeme strings.
    // Only free the *slice* here (no Tokenizer.freeTokens).
    defer allocator.free(tokens);

    // Parse → AST takes ownership of token lexemes
    var ast = try docz.Parser.parse(tokens, allocator);
    defer ast.deinit();

    // Render
    const html = try docz.Renderer.renderHTML(&ast, allocator);
    defer allocator.free(html);

    std.debug.print("🖨️  Rendered HTML:\n{s}\n", .{html});

    // Assertions
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h3>Render Test</h3>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "const x = 9;"));
}
