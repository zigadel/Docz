const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const TokenType = @import("tokenizer.zig").TokenType;
const ASTNode = @import("ast.zig").ASTNode;
const NodeType = @import("ast.zig").NodeType;

pub fn parse(tokens: []const Token, allocator: *std.mem.Allocator) !ASTNode {
    var root = ASTNode.init(allocator, NodeType.Document);

    var i: usize = 0;
    while (i < tokens.len) {
        const tok = tokens[i];

        if (tok.kind == .Directive) {
            var node_type: NodeType = NodeType.Content;
            if (std.mem.eql(u8, tok.lexeme, "@heading")) {
                node_type = NodeType.Heading;
            } else if (std.mem.eql(u8, tok.lexeme, "@meta")) {
                node_type = NodeType.Meta;
            } else if (std.mem.eql(u8, tok.lexeme, "@code")) {
                node_type = NodeType.CodeBlock;
            } else if (std.mem.eql(u8, tok.lexeme, "@math")) {
                node_type = NodeType.Math;
            } else if (std.mem.eql(u8, tok.lexeme, "@image")) {
                node_type = NodeType.Media;
            } else if (std.mem.eql(u8, tok.lexeme, "@style")) {
                node_type = NodeType.Style;
            } else if (std.mem.eql(u8, tok.lexeme, "@import")) {
                node_type = NodeType.Import;
            }

            var node = ASTNode.init(allocator, node_type);

            // Parse parameters
            while (i + 2 < tokens.len and tokens[i + 1].kind == .ParameterKey) {
                try node.attributes.put(tokens[i + 1].lexeme, tokens[i + 2].lexeme);
                i += 2;
            }

            // Parse block content
            if (i + 1 < tokens.len and tokens[i + 1].kind == .Content) {
                node.content = tokens[i + 1].lexeme;
                i += 1;
            }

            try root.children.append(node);
        } else if (tok.kind == .Content) {
            var content_node = ASTNode.init(allocator, NodeType.Content);
            content_node.content = tok.lexeme;
            try root.children.append(content_node);
        }

        i += 1;
    }

    return root;
}

// ----------------------
// Tests
// ----------------------

test "Parse multiple directives" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = gpa.allocator();

    const tokenizer = @import("tokenizer.zig");
    const input =
        \\@meta(title="Docz Guide", author="Team") @end
        \\@heading(level=2) Hello Docz @end
        \\@code(language="zig")
        \\const x = 42;
        \\@end
    ;
    const tokens = try tokenizer.tokenize(input, allocator);
    defer allocator.free(tokens);

    const ast = try parse(tokens, allocator);
    defer ast.children.deinit();

    try std.testing.expect(ast.children.items.len >= 3);
    try std.testing.expectEqual(ast.children.items[0].node_type, NodeType.Meta);
    try std.testing.expectEqual(ast.children.items[1].node_type, NodeType.Heading);
    try std.testing.expectEqual(ast.children.items[2].node_type, NodeType.CodeBlock);
}
