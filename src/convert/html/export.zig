const std = @import("std");
const docz = @import("docz"); // <— instead of ../../parser/ast.zig
const ASTNode = docz.AST.ASTNode;
const NodeType = docz.AST.NodeType;

// -------------------------
// Helpers (top-level only)
// -------------------------

fn writeHeadFromMeta(root: *const ASTNode, w: anytype) !void {
    // Title + generic meta tags come from Meta nodes
    var wrote_title = false;

    for (root.children.items) |node| {
        if (node.node_type != .Meta) continue;

        var it = node.attributes.iterator();
        while (it.next()) |entry| {
            const k = entry.key_ptr.*;
            const v = entry.value_ptr.*;
            if (std.ascii.eqlIgnoreCase(k, "title")) {
                if (!wrote_title) {
                    try w.print("<title>{s}</title>\n", .{v});
                    wrote_title = true;
                }
            } else {
                try w.print("<meta name=\"{s}\" content=\"{s}\">\n", .{ k, v });
            }
        }
    }
}

fn writeImports(root: *const ASTNode, w: anytype) !void {
    // Minimal: only link rel=stylesheet for Import nodes (href)
    for (root.children.items) |node| {
        if (node.node_type != .Import) continue;
        const href = node.attributes.get("href") orelse "";
        if (href.len != 0) {
            try w.print("<link rel=\"stylesheet\" href=\"{s}\">\n", .{href});
        }
    }
}

fn writeBodyFromAst(root: *const ASTNode, w: anytype) !void {
    for (root.children.items) |node| {
        switch (node.node_type) {
            .Meta => {
                // Meta already emitted in <head>.
            },
            .Heading => {
                const level = node.attributes.get("level") orelse "1";
                const text = std.mem.trimRight(u8, node.content, " \t\r\n");
                try w.print("<h{s}>{s}</h{s}>\n", .{ level, text, level });
            },
            .Content => {
                const text = std.mem.trimRight(u8, node.content, " \t\r\n");
                if (text.len != 0) try w.print("<p>{s}</p>\n", .{text});
            },
            .CodeBlock => {
                try w.print("<pre><code>{s}</code></pre>\n", .{node.content});
            },
            .Math => {
                // Minimal math wrapper; client picks renderer (KaTeX/MathJax/etc.)
                try w.print("<div class=\"math\">{s}</div>\n", .{node.content});
            },
            .Media => {
                const src = node.attributes.get("src") orelse "";
                if (src.len != 0) try w.print("<img src=\"{s}\" />\n", .{src});
            },
            .Import => {
                // already emitted in <head>
            },
            .Style => {
                // strict/minimal exporter: ignore Style nodes altogether
            },
            else => {
                // leave a comment for unhandled node types
                try w.print("<!-- Unhandled node: {s} -->\n", .{@tagName(node.node_type)});
            },
        }
    }
}

// -------------------------
// Public API
// -------------------------

/// Export AST -> minimal HTML5 document.
/// - Meta nodes produce <title> / <meta name="…" content="…">
/// - Import nodes (href) become <link rel="stylesheet" …>
/// - Style nodes are ignored (strict/minimal mode)
pub fn exportHtml(doc: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const w = out.writer();

    try w.writeAll("<!DOCTYPE html>\n<html>\n<head>\n");
    try writeHeadFromMeta(doc, w);
    try writeImports(doc, w);
    try w.writeAll("</head>\n<body>\n");
    try writeBodyFromAst(doc, w);
    try w.writeAll("</body>\n</html>\n");

    return out.toOwnedSlice();
}

// -------------------------
// Unit tests
// -------------------------

test "html_export: emits title/meta/import and basic body" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    // Build a tiny AST
    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    // Meta
    {
        var meta = ASTNode.init(A, NodeType.Meta);
        try meta.attributes.put("title", "Hello");
        try meta.attributes.put("author", "Docz Team");
        try root.children.append(meta);
    }
    // Import (stylesheet)
    {
        var imp = ASTNode.init(A, NodeType.Import);
        try imp.attributes.put("href", "/styles/site.css");
        try root.children.append(imp);
    }
    // Body: heading, para, code, math, image
    {
        var h = ASTNode.init(A, NodeType.Heading);
        try h.attributes.put("level", "1");
        h.content = "Welcome";
        try root.children.append(h);

        var p = ASTNode.init(A, NodeType.Content);
        p.content = "First paragraph.";
        try root.children.append(p);

        var cb = ASTNode.init(A, NodeType.CodeBlock);
        cb.content = "const x = 7;";
        try root.children.append(cb);

        var m = ASTNode.init(A, NodeType.Math);
        m.content = "E = mc^2";
        try root.children.append(m);

        var img = ASTNode.init(A, NodeType.Media);
        try img.attributes.put("src", "logo.png");
        try root.children.append(img);
    }

    const html = try exportHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<title>Hello</title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<meta name=\"author\" content=\"Docz Team\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<link rel=\"stylesheet\" href=\"/styles/site.css\">") != null);

    try std.testing.expect(std.mem.indexOf(u8, html, "<h1>Welcome</h1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<p>First paragraph.</p>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<pre><code>const x = 7;</code></pre>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<div class=\"math\">E = mc^2</div>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<img src=\"logo.png\" />") != null);
}

test "html_export: ignores Style nodes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    // Style node should be ignored
    {
        var s = ASTNode.init(A, NodeType.Style);
        s.content = "font-size=12px";
        try root.children.append(s);
    }

    const html = try exportHtml(&root, A);
    defer A.free(html);

    // Style content should not appear
    try std.testing.expect(std.mem.indexOf(u8, html, "font-size=12px") == null);
}
