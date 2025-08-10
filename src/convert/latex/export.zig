const std = @import("std");
const docz = @import("docz"); // <— instead of ../../parser/ast.zig
const ASTNode = docz.AST.ASTNode;
const NodeType = docz.AST.NodeType;

// ---------- helpers (decl-level; no nesting) ----------
fn styleKeyPriority(k: []const u8) u8 {
    if (std.mem.eql(u8, k, "font-size")) return 0;
    if (std.mem.eql(u8, k, "color")) return 1;
    return 100;
}

fn styleKeyLess(_: void, a: []const u8, b: []const u8) bool {
    const pa = styleKeyPriority(a);
    const pb = styleKeyPriority(b);
    if (pa != pb) return pa < pb;
    return std.mem.lessThan(u8, a, b);
}

/// Converts attributes → inline CSS string; excludes non-style keys (like "mode")
fn buildInlineStyle(attributes: std.StringHashMap([]const u8), allocator: std.mem.Allocator) ![]u8 {
    var keys = std.ArrayList([]const u8).init(allocator);
    defer keys.deinit();

    var it = attributes.iterator();
    while (it.next()) |entry| {
        const k = entry.key_ptr.*;
        if (std.mem.eql(u8, k, "mode")) continue;
        try keys.append(k);
    }

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
    try w.print(";", .{});
    return out.toOwnedSlice();
}

/// Converts style-def content into CSS rules (simple "class: k=v, k2=v2" lines)
fn buildGlobalCSS(style_content: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var builder = std.ArrayList(u8).init(allocator);
    const writer = builder.writer();

    var lines = std.mem.tokenizeScalar(u8, style_content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        const colon_index = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
        const class_name = std.mem.trim(u8, trimmed[0..colon_index], " \t");
        const props_raw = std.mem.trim(u8, trimmed[colon_index + 1 ..], " \t");

        try writer.print(".{s} {{ ", .{class_name});

        var props_iter = std.mem.tokenizeScalar(u8, props_raw, ',');
        var first = true;
        while (props_iter.next()) |prop| {
            const clean = std.mem.trim(u8, prop, " \t");
            const eq_i = std.mem.indexOfScalar(u8, clean, '=') orelse continue;
            const key = std.mem.trim(u8, clean[0..eq_i], " \t");
            const value = std.mem.trim(u8, clean[eq_i + 1 ..], " \t\"");
            if (!first) try writer.print(" ", .{});
            try writer.print("{s}:{s};", .{ key, value });
            first = false;
        }

        try writer.print(" }}\n", .{});
    }

    return builder.toOwnedSlice();
}

// ---------- public API ----------
pub fn exportToHtml(root: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const w = out.writer();

    try w.writeAll("<!DOCTYPE html>\n<html>\n<head>\n");

    // Head: <title>, <meta>, <style> (global)
    // Title/meta collected from Meta nodes; CSS aggregated from Style(mode="global")
    // First pass: meta + title
    for (root.children.items) |node| {
        if (node.node_type == .Meta) {
            var it = node.attributes.iterator();
            while (it.next()) |entry| {
                const k = entry.key_ptr.*;
                const v = entry.value_ptr.*;
                if (std.mem.eql(u8, k, "title")) {
                    try w.print("<title>{s}</title>\n", .{v});
                } else {
                    try w.print("<meta name=\"{s}\" content=\"{s}\">\n", .{ k, v });
                }
            }
        }
    }

    // Second pass: global CSS
    var global_css_buf = std.ArrayList(u8).init(allocator);
    const g = global_css_buf.writer();
    for (root.children.items) |node| {
        if (node.node_type == .Style) {
            if (node.attributes.get("mode")) |mode| {
                if (std.mem.eql(u8, mode, "global")) {
                    const css = try buildGlobalCSS(node.content, allocator);
                    defer allocator.free(css);
                    try g.print("{s}\n", .{css});
                }
            }
        }
    }
    if (global_css_buf.items.len != 0) {
        try w.print("<style>\n{s}</style>\n", .{global_css_buf.items});
    }
    global_css_buf.deinit();

    try w.writeAll("</head>\n<body>\n");

    // Body: render supported nodes
    for (root.children.items) |node| {
        switch (node.node_type) {
            .Meta => {}, // already handled in <head>
            .Heading => {
                const level = node.attributes.get("level") orelse "1";
                const text = std.mem.trimRight(u8, node.content, " \t\r\n");
                try w.print("<h{s}>{s}</h{s}>\n", .{ level, text, level });
            },
            .Content => {
                try w.print("<p>{s}</p>\n", .{node.content});
            },
            .CodeBlock => {
                try w.print("<pre><code>{s}</code></pre>\n", .{node.content});
            },
            .Math => {
                try w.print("<div class=\"math\">{s}</div>\n", .{node.content});
            },
            .Media => {
                const src = node.attributes.get("src") orelse "";
                try w.print("<img src=\"{s}\" />\n", .{src});
            },
            .Import => {
                // Treat as CSS link for HTML export
                const href = node.attributes.get("href") orelse "";
                try w.print("<link rel=\"stylesheet\" href=\"{s}\">\n", .{href});
            },
            .Style => {
                if (node.attributes.get("mode")) |mode| {
                    if (std.mem.eql(u8, mode, "inline")) {
                        const inline_css = try buildInlineStyle(node.attributes, allocator);
                        defer allocator.free(inline_css);
                        try w.print("<span style=\"{s}\">{s}</span>\n", .{ inline_css, node.content });
                    } else {
                        // global already handled
                    }
                }
            },
            else => {
                try w.print("<!-- Unhandled node: {s} -->\n", .{@tagName(node.node_type)});
            },
        }
    }

    try w.writeAll("</body>\n</html>\n");
    return out.toOwnedSlice();
}

// ---------- tests ----------
test "exportToHtml: minimal document with meta, heading, code" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    // @meta(title="Hello")
    {
        var m = ASTNode.init(A, NodeType.Meta);
        try m.attributes.put("title", "Hello");
        try root.children.append(m);
    }
    // <h1>Welcome</h1>
    {
        var h = ASTNode.init(A, NodeType.Heading);
        try h.attributes.put("level", "1");
        h.content = "Welcome";
        try root.children.append(h);
    }
    // <pre><code>…</code></pre>
    {
        var c = ASTNode.init(A, NodeType.CodeBlock);
        c.content = "const x = 42;";
        try root.children.append(c);
    }

    const html = try exportToHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<title>Hello</title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<h1>Welcome</h1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<pre><code>const x = 42;</code></pre>") != null);
}

test "exportToHtml: global + inline styles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    {
        var s = ASTNode.init(A, NodeType.Style);
        try s.attributes.put("mode", "global");
        s.content =
            \\heading-level-1: font-size=36px, font-weight=bold
            \\body-text: font-family="Inter", line-height=1.6
        ;
        try root.children.append(s);
    }
    {
        var s = ASTNode.init(A, NodeType.Style);
        try s.attributes.put("mode", "inline");
        try s.attributes.put("font-size", "18px");
        try s.attributes.put("color", "blue");
        s.content = "Styled";
        try root.children.append(s);
    }

    const html = try exportToHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, ".heading-level-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "style=\"font-size:18px;color:blue;\"") != null);
}
