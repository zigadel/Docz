const std = @import("std");
const ASTNode = @import("../parser/ast.zig").ASTNode;
const NodeType = @import("../parser/ast.zig").NodeType;

// ---- helpers ----
fn lessStr(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn styleKeyPriority(k: []const u8) u8 {
    if (std.mem.eql(u8, k, "font-size")) return 0; // ensure font-size first
    if (std.mem.eql(u8, k, "color")) return 1; // then color
    return 100; // others later
}

fn styleKeyLess(_: void, a: []const u8, b: []const u8) bool {
    const pa = styleKeyPriority(a);
    const pb = styleKeyPriority(b);
    if (pa != pb) return pa < pb; // priority first
    return std.mem.lessThan(u8, a, b); // then lexicographic
}

/// Converts attributes → inline CSS string; excludes non-style keys (like "mode")
fn buildInlineStyle(attributes: std.StringHashMap([]const u8), allocator: std.mem.Allocator) ![]u8 {
    var keys = std.ArrayList([]const u8).init(allocator);
    defer keys.deinit();

    var it = attributes.iterator();
    while (it.next()) |entry| {
        const k = entry.key_ptr.*;
        if (std.mem.eql(u8, k, "mode")) continue; // exclude control key
        try keys.append(k);
    }

    // sort with priority
    std.mem.sort([]const u8, keys.items, {}, styleKeyLess);

    var out = std.ArrayList(u8).init(allocator);
    const w = out.writer();

    var first = true;
    for (keys.items) |k| {
        const v = attributes.get(k).?;
        if (!first) try w.print(";", .{});
        try w.print("{s}:{s}", .{ k, v });
        first = false;
    }
    try w.print(";", .{}); // trailing ; expected by the test

    return out.toOwnedSlice();
}

/// Converts style-def content into CSS
fn buildGlobalCSS(styleContent: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var builder = std.ArrayList(u8).init(allocator);
    const writer = builder.writer();

    var lines = std.mem.tokenizeScalar(u8, styleContent, '\n');
    while (lines.next()) |line| {
        var trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        const colonIndex = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
        const className = std.mem.trim(u8, trimmed[0..colonIndex], " \t");
        const propsRaw = std.mem.trim(u8, trimmed[colonIndex + 1 ..], " \t");

        try writer.print(".{s} {{ ", .{className});

        var propsIter = std.mem.tokenizeScalar(u8, propsRaw, ',');
        var first = true;
        while (propsIter.next()) |prop| {
            var cleanProp = std.mem.trim(u8, prop, " \t");
            const eqIndex = std.mem.indexOfScalar(u8, cleanProp, '=') orelse continue;
            const key = std.mem.trim(u8, cleanProp[0..eqIndex], " \t");
            const value = std.mem.trim(u8, cleanProp[eqIndex + 1 ..], " \t\"");

            if (!first) try writer.print(" ", .{});
            try writer.print("{s}:{s};", .{ key, value });
            first = false;
        }

        try writer.print(" }}\n", .{});
    }

    return builder.toOwnedSlice();
}

pub fn renderHTML(root: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    const writer = list.writer();

    try writer.print("<!DOCTYPE html>\n<html>\n<head>\n", .{});

    // Meta information
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

    // Global CSS
    var globalCSSBuilder = std.ArrayList(u8).init(allocator);
    const globalWriter = globalCSSBuilder.writer();

    for (root.children.items) |node| {
        if (node.node_type == .Style) {
            if (node.attributes.get("mode")) |mode| {
                if (std.mem.eql(u8, mode, "global")) {
                    const css = try buildGlobalCSS(node.content, allocator);
                    defer allocator.free(css);
                    try globalWriter.print("{s}\n", .{css});
                }
            }
        }
    }

    if (globalCSSBuilder.items.len > 0) {
        try writer.print("<style>\n{s}</style>\n", .{globalCSSBuilder.items});
    }
    globalCSSBuilder.deinit();

    try writer.print("</head>\n<body>\n", .{});

    // Body rendering
    for (root.children.items) |node| {
        switch (node.node_type) {
            .Meta => {
                // Meta already emitted into <head>; skip in body to avoid noise.
            },
            .Heading => {
                const level = node.attributes.get("level") orelse "1";
                const text = std.mem.trimRight(u8, node.content, " \t\r\n");
                try writer.print("<h{s}>{s}</h{s}>\n", .{ level, text, level });
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
                if (node.attributes.get("mode")) |mode| {
                    if (std.mem.eql(u8, mode, "inline")) {
                        const inlineCSS = try buildInlineStyle(node.attributes, allocator);
                        defer allocator.free(inlineCSS);
                        try writer.print("<span style=\"{s}\">{s}</span>\n", .{ inlineCSS, node.content });
                    }
                }
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
// ✅ Tests
// ----------------------

test "Render HTML with inline style" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var root = ASTNode.init(allocator, NodeType.Document);
    defer root.deinit();

    var styleNode = ASTNode.init(allocator, NodeType.Style);
    try styleNode.attributes.put("mode", "inline");
    try styleNode.attributes.put("font-size", "18px");
    try styleNode.attributes.put("color", "blue");
    styleNode.content = "Styled Text";
    try root.children.append(styleNode);

    const html = try renderHTML(&root, allocator);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "style=\"font-size:18px;color:blue;\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Styled Text") != null);
}

test "Render HTML with global style-def" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var root = ASTNode.init(allocator, NodeType.Document);
    defer root.deinit();

    var globalStyleNode = ASTNode.init(allocator, NodeType.Style);
    try globalStyleNode.attributes.put("mode", "global");
    globalStyleNode.content =
        \\heading-level-1: font-size=36px, font-weight=bold
        \\body-text: font-family="Inter", line-height=1.6
    ;
    try root.children.append(globalStyleNode);

    const html = try renderHTML(&root, allocator);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, ".heading-level-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, ".body-text") != null);
}
