const std = @import("std");

pub const NodeType = enum {
    Document,
    Meta,
    Heading,
    Content,
    CodeBlock,
    Math,
    Media,
    Import,
    Style,
};

pub const ASTNode = struct {
    node_type: NodeType,
    content: []const u8 = "",
    owns_content: bool = false,
    allocator: ?std.mem.Allocator = null,
    attributes: std.StringHashMap([]const u8),
    children: std.ArrayList(ASTNode),

    pub fn init(allocator: std.mem.Allocator, node_type: NodeType) ASTNode {
        return ASTNode{
            .node_type = node_type,
            .content = "",
            .owns_content = false,
            .allocator = allocator,
            .attributes = std.StringHashMap([]const u8).init(allocator),
            .children = std.ArrayList(ASTNode).init(allocator),
        };
    }

    pub fn deinit(self: *ASTNode) void {
        // children first
        var i: usize = 0;
        while (i < self.children.items.len) : (i += 1) {
            self.children.items[i].deinit();
        }
        self.children.deinit();
        self.attributes.deinit();

        // free content if we own it
        if (self.owns_content and self.content.len > 0) {
            if (self.allocator) |a| a.free(self.content);
        }
    }

    pub fn addChild(self: *ASTNode, child: ASTNode) !void {
        try self.children.append(child);
    }
};

// -------------
// Unit Tests
// -------------
test "ASTNode init and deinit with attributes and children" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var root = ASTNode.init(allocator, .Document);
    defer root.deinit();

    var heading = ASTNode.init(allocator, .Heading);
    heading.content = "Docz Title";
    try heading.attributes.put("level", "2");
    try root.addChild(heading);

    try std.testing.expect(root.children.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, root.children.items[0].content, "Docz Title"));
    try std.testing.expect(root.children.items[0].attributes.contains("level"));
}
