const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const TokenType = @import("tokenizer.zig").TokenType;
const ASTNode = @import("ast.zig").ASTNode;
const NodeType = @import("ast.zig").NodeType;

/// Maps a directive string (e.g. "@meta") to a NodeType.
/// Includes simple aliases like "@css" → Style.
fn directiveToNodeType(directive: []const u8) NodeType {
    if (std.mem.eql(u8, directive, "@meta")) return NodeType.Meta;
    if (std.mem.eql(u8, directive, "@heading")) return NodeType.Heading;
    if (std.mem.eql(u8, directive, "@code")) return NodeType.CodeBlock;
    if (std.mem.eql(u8, directive, "@math")) return NodeType.Math;
    if (std.mem.eql(u8, directive, "@image")) return NodeType.Media;
    if (std.mem.eql(u8, directive, "@import")) return NodeType.Import;
    if (std.mem.eql(u8, directive, "@style")) return NodeType.Style;

    // Aliases / planned:
    if (std.mem.eql(u8, directive, "@css")) return NodeType.Style; // alias of style
    if (std.mem.eql(u8, directive, "@style-def")) return NodeType.StyleDef;

    // Fallback: treat as generic content; unknowns can be upgraded later
    return NodeType.Content;
}

fn isBlockDirective(nt: NodeType) bool {
    return switch (nt) {
        .CodeBlock, .Math, .Style, .Css, .StyleDef => true,
        else => false,
    };
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

            // parameters
            while (i + 1 < tokens.len and tokens[i].kind == .ParameterKey and tokens[i + 1].kind == .ParameterValue) {
                try node.attributes.put(tokens[i].lexeme, tokens[i + 1].lexeme);
                i += 2;
            }

            // inline content (e.g. heading title after ")")
            if (i < tokens.len and tokens[i].kind == .Content) {
                node.content = tokens[i].lexeme; // not owned
                node.owns_content = false;
                i += 1;
            }

            // block body for fenced directives
            if (isBlockDirective(node_type)) {
                var block = std.ArrayList(u8).init(allocator);
                defer block.deinit();

                while (i < tokens.len and tokens[i].kind != .BlockEnd) : (i += 1) {
                    try block.appendSlice(tokens[i].lexeme);
                    try block.append('\n');
                }
                if (i < tokens.len and tokens[i].kind == .BlockEnd) {
                    i += 1; // skip @end
                }

                if (block.items.len > 0) {
                    node.content = try block.toOwnedSlice();
                    node.owns_content = true; // we allocated it
                }
            }

            try root.children.append(node);
            continue;
        }

        if (tok.kind == .Content) {
            var content_node = ASTNode.init(allocator, .Content);
            content_node.content = tok.lexeme; // not owned
            try root.children.append(content_node);
            i += 1;
            continue;
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
