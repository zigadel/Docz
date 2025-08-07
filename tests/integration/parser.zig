const std = @import("std");
const docz = @import("docz");

test "integration: parser builds AST from token list" {
    const input =
        \\@heading(level=2) Heading @end
        \\Some paragraph text with *emphasis*.
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const tokens = try docz.Tokenizer.tokenize(input, allocator);
    defer docz.Tokenizer.freeTokens(allocator, tokens);

    var ast = try docz.Parser.parse(tokens, allocator);
    defer ast.deinit();

    std.debug.print("🌲 AST has {d} top-level nodes\n", .{ast.children.items.len});
    try std.testing.expect(ast.children.items.len >= 1);
}
