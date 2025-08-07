const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const TokenType = @import("tokenizer.zig").TokenType;
const ASTNode = @import("ast.zig").ASTNode;
const NodeType = @import("ast.zig").NodeType;

/// Maps a directive string (e.g. "@meta") to a NodeType
fn directiveToNodeType(directive: []const u8) NodeType {
    return if (std.mem.eql(u8, directive, "@meta")) NodeType.Meta else if (std.mem.eql(u8, directive, "@heading")) NodeType.Heading else if (std.mem.eql(u8, directive, "@code")) NodeType.CodeBlock else if (std.mem.eql(u8, directive, "@math")) NodeType.Math else if (std.mem.eql(u8, directive, "@image")) NodeType.Media else if (std.mem.eql(u8, directive, "@import")) NodeType.Import else if (std.mem.eql(u8, directive, "@style")) NodeType.Style else NodeType.Content;
}

/// Parses tokens into an ASTNode tree
pub fn parse(tokens: []const Token, allocator: std.mem.Allocator) !ASTNode {
    var root = ASTNode.init(allocator, .Document);

    var i: usize = 0;
    while (i < tokens.len) {
        const tok = tokens[i];

        if (tok.kind == .Directive) {
            const node_type = directiveToNodeType(tok.lexeme);
            var node = ASTNode.init(allocator, node_type);

            i += 1;

            // Parse attribute key-value pairs (e.g. title="Docz")
            while (i + 1 < tokens.len and tokens[i].kind == .ParameterKey and tokens[i + 1].kind == .ParameterValue) {
                try node.attributes.put(tokens[i].lexeme, tokens[i + 1].lexeme);
                i += 2;
            }

            // Capture inline content
            if (i < tokens.len and tokens[i].kind == .Content) {
                node.content = tokens[i].lexeme;
                i += 1;
            }

            // Capture multiline block content until @end
            if (i < tokens.len and tokens[i].kind != .Directive and node_type != .Meta and node_type != .Import) {
                var block_content = std.ArrayList(u8).init(allocator);
                while (i < tokens.len and !std.mem.eql(u8, tokens[i].lexeme, "@end")) : (i += 1) {
                    try block_content.appendSlice(tokens[i].lexeme);
                    try block_content.append('\n');
                }
                if (i < tokens.len and std.mem.eql(u8, tokens[i].lexeme, "@end")) {
                    i += 1;
                }
                node.content = try block_content.toOwnedSlice();
            }

            try root.children.append(node);
        } else if (tok.kind == .Content) {
            var content_node = ASTNode.init(allocator, .Content);
            content_node.content = tok.lexeme;
            try root.children.append(content_node);
            i += 1;
        } else {
            i += 1;
        }
    }

    return root;
}

// ----------------------
// Tests
// ----------------------
test "Parse multiple directives" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const tokenizer = @import("tokenizer.zig");
    const input =
        \\@meta(title="Docz Guide", author="Team") @end
        \\@heading(level=2) Welcome to Docz @end
        \\@code(language="zig")
        \\const x = 42;
        \\@end
    ;
    const tokens = try tokenizer.tokenize(input, allocator);
    defer allocator.free(tokens);

    var ast = try parse(tokens, allocator);
    defer ast.deinit();

    try std.testing.expectEqual(ast.children.items.len, 3);
    try std.testing.expectEqual(ast.children.items[0].node_type, .Meta);
    try std.testing.expectEqual(ast.children.items[1].node_type, .Heading);
    try std.testing.expectEqual(ast.children.items[2].node_type, .CodeBlock);

    try std.testing.expect(std.mem.containsAtLeast(u8, ast.children.items[2].content, 1, "const x = 42;"));
}
