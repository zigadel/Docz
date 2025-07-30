const std = @import("std");

pub const NodeType = enum {
    Document,
    Meta,
    Heading,
    CodeBlock,
    Style,
    Import,
    Math,
    Media,
    Content,
};

pub const ASTNode = struct {
    node_type: NodeType,
    attributes: std.StringHashMap([]const u8),
    content: []const u8,
    children: std.ArrayList(ASTNode),

    pub fn init(allocator: *std.mem.Allocator, node_type: NodeType) ASTNode {
        return ASTNode{
            .node_type = node_type,
            .attributes = std.StringHashMap([]const u8).init(allocator),
            .content = "",
            .children = std.ArrayList(ASTNode).init(allocator),
        };
    }
};
                                                                                                                        