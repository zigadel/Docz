const std = @import("std");
const docz = @import("docz");

test "🔁 Full pipeline integration: .dcz input → HTML output" {
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

    std.debug.print("\n🔧 Tokenizing...\n", .{});
    const tokens = try docz.Tokenizer.tokenize(input_docz, allocator);
    defer docz.Tokenizer.freeTokens(allocator, tokens);
    std.debug.print("✅ Tokenized {d} tokens\n", .{tokens.len});

    std.debug.print("\n🧠 Parsing to AST...\n", .{});
    var ast = try docz.Parser.parse(tokens, allocator);
    defer ast.deinit();
    std.debug.print("✅ AST contains {d} top-level nodes\n", .{ast.children.items.len});

    std.debug.print("\n🎨 Rendering HTML...\n", .{});
    const html = try docz.Renderer.renderHTML(&ast, allocator);
    defer allocator.free(html);
    std.debug.print("✅ HTML output size: {d} bytes\n", .{html.len});

    std.debug.print("\n🔍 Checking HTML contents...\n", .{});
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h2>Hello, Docz!</h2>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "const x = 123;"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "Integration Test"));
    std.debug.print("✅ All checks passed.\n", .{});
}
