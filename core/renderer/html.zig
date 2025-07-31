const std = @import("std");
const ASTNode = @import("../parser/ast.zig").ASTNode;
const NodeType = @import("../parser/ast.zig").NodeType;

pub fn renderHTML(root: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    const writer = list.writer();

    try writer.print("<!DOCTYPE html>\n<html>\n<head>\n", .{});

    // Render meta info if present
    for (root.children.items) |node| {
        if (node.node_type == .Meta) {
            var it = node.attributes.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, "title")) {
                    try writer.print("<title>{s}</title>\n", .{entry.value_ptr.*});
                } else {
                    try writer.print("<meta name=\"{s}\" content=\"{s}\">\n", .{
                        entry.key_ptr.*, entry.value_ptr.*,
                    });
                }
            }
        }
    }

    try writer.print("</head>\n<body>\n", .{});

    // Render body content
    for (root.children.items) |node| {
        switch (node.node_type) {
            .Heading => {
                const level = node.attributes.get("level") orelse "1";
                try writer.print("<h{s}>{s}</h{s}>\n", .{ level, node.content, level });
            },
            .Content => {
                try writer.print("<p>{s}</p>\n", .{node.content});
            },
            .CodeBlock => {
                try writer.print("<pre><code>{s}</code></pre>\n", .{node.content});
            },
            .Math => {
                try writer.print("<div class=\"math\">{s}</div>\n", .{node.content});
            },
            .Media => {
                const src = node.attributes.get("src") orelse "";
                try writer.print("<img src=\"{s}\" />\n", .{src});
            },
            .Import => {
                const path = node.attributes.get("href") orelse "";
                try writer.print("<link rel=\"stylesheet\" href=\"{s}\">\n", .{path});
            },
            .Style => {
                try writer.print("<style>{s}</style>\n", .{node.content});
            },
            else => {
                try writer.print("<!-- Unhandled node: {s} -->\n", .{@tagName(node.node_type)});
            },
        }
    }

    try writer.print("</body>\n</html>\n", .{});
    return list.toOwnedSlice();
}

// ----------------------
// Tests
// ----------------------
test "Render HTML for multiple node types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var root = ASTNode.init(allocator, NodeType.Document);
    defer {
        for (root.children.items) |*child| {
            child.attributes.deinit();
            child.children.deinit();
        }
        root.children.deinit();
    }

    var heading = ASTNode.init(allocator, NodeType.Heading);
    try heading.attributes.put("level", "2");
    heading.content = "Hello World";
    try root.children.append(heading);

    var code = ASTNode.init(allocator, NodeType.CodeBlock);
    code.content = "const x = 42;";
    try root.children.append(code);

    const html = try renderHTML(&root, allocator);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<h2>Hello World</h2>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<pre><code>const x = 42;</code></pre>") != null);
}
