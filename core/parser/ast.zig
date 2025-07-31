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

    pub fn init(allocator: std.mem.Allocator, node_type: NodeType) ASTNode {
        return ASTNode{
            .node_type = node_type,
            .attributes = std.StringHashMap([]const u8).init(allocator),
            .content = "",
            .children = std.ArrayList(ASTNode).init(allocator),
        };
    }

    /// Recursively free all child nodes, attributes, and the array list itself
    pub fn deinit(self: *ASTNode) void {
        // Free attributes
        self.attributes.deinit();

        // Recursively free children
        for (self.children.items) |*child| {
            child.deinit();
        }

        // Free children array
        self.children.deinit();
    }
};
