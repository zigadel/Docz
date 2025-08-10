const std = @import("std");
const docz = @import("docz");
const ASTNode = docz.AST.ASTNode;
const NodeType = docz.AST.NodeType;

// -------------------------
// Helpers
// -------------------------

fn trimRightNl(s: []const u8) []const u8 {
    return std.mem.trimRight(u8, s, " \t\r\n");
}

fn clampHeadingLevel(lvl_raw: u8) u8 {
    return if (lvl_raw < 1) 1 else if (lvl_raw > 6) 6 else lvl_raw;
}

/// Escape LaTeX special characters in normal text (headings/paragraphs).
/// Code/Math/Media are NOT escaped.
fn latexEscape(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        switch (c) {
            '\\' => try out.appendSlice("\\textbackslash{}"),
            '{' => try out.appendSlice("\\{"),
            '}' => try out.appendSlice("\\}"),
            '%' => try out.appendSlice("\\%"),
            '&' => try out.appendSlice("\\&"),
            '$' => try out.appendSlice("\\$"),
            '#' => try out.appendSlice("\\#"),
            '_' => try out.appendSlice("\\_"),
            '^' => try out.appendSlice("\\textasciicircum{}"),
            '~' => try out.appendSlice("\\textasciitilde{}"),
            else => try out.append(c),
        }
    }
    return out.toOwnedSlice();
}

fn writeParagraph(w: anytype, text: []const u8, alloc: std.mem.Allocator) !void {
    const t = trimRightNl(text);
    if (t.len == 0) return;
    const esc = try latexEscape(alloc, t);
    defer alloc.free(esc);
    try std.fmt.format(w, "{s}\n\n", .{esc});
}

fn writeHeading(w: anytype, level_str: []const u8, text: []const u8, alloc: std.mem.Allocator) !void {
    const lvl_u = std.fmt.parseUnsigned(u8, level_str, 10) catch 1;
    const lvl = clampHeadingLevel(lvl_u);

    const cmd: []const u8 = switch (lvl) {
        1 => "\\section",
        2 => "\\subsection",
        else => "\\subsubsection",
    };

    const t = trimRightNl(text);
    const esc = try latexEscape(alloc, t);
    defer alloc.free(esc);
    // {cmd}{text}  →  \section{My Title}
    try std.fmt.format(w, "{s}{{{s}}}\n\n", .{ cmd, esc });
}

fn writeCodeBlock(w: anytype, body: []const u8) !void {
    // Code: raw
    try std.fmt.format(w, "\\begin{{verbatim}}\n{s}\n\\end{{verbatim}}\n\n", .{body});
}

fn writeMath(w: anytype, body: []const u8) !void {
    // Math: raw body, importer already normalizes whitespace on the way back
    const b = trimRightNl(body);
    if (b.len == 0) return;
    try std.fmt.format(w, "\\begin{{equation}}\n{s}\n\\end{{equation}}\n\n", .{b});
}

fn writeImage(w: anytype, src: []const u8) !void {
    // Media: keep src raw (filenames often contain underscores; escaping would break)
    if (src.len == 0) return;
    try std.fmt.format(w, "\\includegraphics{{{s}}}\n\n", .{src});
}

// -------------------------
// Public API
// -------------------------

/// Export AST -> minimal LaTeX.
/// Notes:
/// - Only emits \title and \author if present in Meta nodes.
/// - Headings > 3 are clamped to \subsubsection.
/// - Content/Heading text are LaTeX-escaped; Code/Math/Media are not.
/// - Unknown nodes are ignored.
pub fn exportAstToLatex(doc: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const w = out.writer();

    var title_emitted = false;
    var author_emitted = false;

    // Pass 1: gather title/author from Meta nodes
    for (doc.children.items) |node| {
        if (node.node_type != .Meta) continue;

        if (!title_emitted) {
            if (node.attributes.get("title")) |t| {
                const esc = try latexEscape(allocator, t);
                defer allocator.free(esc);
                try std.fmt.format(w, "\\title{{{s}}}\n", .{esc});
                title_emitted = true;
            }
        }
        if (!author_emitted) {
            if (node.attributes.get("author")) |a| {
                const esc = try latexEscape(allocator, a);
                defer allocator.free(esc);
                try std.fmt.format(w, "\\author{{{s}}}\n", .{esc});
                author_emitted = true;
            }
        }
    }
    if (title_emitted or author_emitted) {
        try w.writeAll("\n");
    }

    // Pass 2: body
    for (doc.children.items) |node| {
        switch (node.node_type) {
            .Meta => {}, // handled above
            .Heading => {
                const level_str = node.attributes.get("level") orelse "1";
                try writeHeading(w, level_str, node.content, allocator);
            },
            .Content => {
                try writeParagraph(w, node.content, allocator);
            },
            .CodeBlock => {
                try writeCodeBlock(w, node.content);
            },
            .Math => {
                try writeMath(w, node.content);
            },
            .Media => {
                const src = node.attributes.get("src") orelse "";
                if (src.len != 0) try writeImage(w, src);
            },
            .Import, .Style => {
                // ignore in LaTeX export (minimal)
            },
            else => {
                // ignore unknown nodes
            },
        }
    }

    // Normalize EOF: ensure trailing single newline
    if (out.items.len == 0 or out.items[out.items.len - 1] != '\n') {
        try out.append('\n');
    }

    return out.toOwnedSlice();
}

// -------------------------
// Unit tests
// -------------------------

test "latex_export: title/author + basic body" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    // Meta
    {
        var m = ASTNode.init(A, NodeType.Meta);
        try m.attributes.put("title", "My Doc");
        try m.attributes.put("author", "Docz Team");
        try root.children.append(m);
    }
    // Body
    {
        var h = ASTNode.init(A, NodeType.Heading);
        try h.attributes.put("level", "2");
        h.content = "Section";
        try root.children.append(h);

        var p = ASTNode.init(A, NodeType.Content);
        p.content = "Hello **world**!";
        try root.children.append(p);

        var cb = ASTNode.init(A, NodeType.CodeBlock);
        cb.content = "const x = 42;";
        try root.children.append(cb);

        var m = ASTNode.init(A, NodeType.Math);
        m.content = "E = mc^2";
        try root.children.append(m);

        var img = ASTNode.init(A, NodeType.Media);
        try img.attributes.put("src", "img/logo.png");
        try root.children.append(img);
    }

    const tex = try exportAstToLatex(&root, A);
    defer A.free(tex);

    try std.testing.expect(std.mem.indexOf(u8, tex, "\\title{My Doc}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\author{Docz Team}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\subsection{Section}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "Hello **world**!\n\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\begin{verbatim}\nconst x = 42;\n\\end{verbatim}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\begin{equation}\nE = mc^2\n\\end{equation}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\includegraphics{img/logo.png}") != null);
}

// NEW: escaping in paragraph + heading
test "latex_export: escape special chars in content and heading" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    {
        var h = ASTNode.init(A, NodeType.Heading);
        try h.attributes.put("level", "1");
        h.content = "Price is $5 & 10% off {today}";
        try root.children.append(h);
    }
    {
        var p = ASTNode.init(A, NodeType.Content);
        p.content = "Path A\\B with #hash _under_ ^caret~tilde";
        try root.children.append(p);
    }
    // Code block should remain raw (no escaping applied)
    {
        var cb = ASTNode.init(A, NodeType.CodeBlock);
        cb.content = "printf(\"100% done\\n\"); // keep % and \\";
        try root.children.append(cb);
    }

    const tex = try exportAstToLatex(&root, A);
    defer A.free(tex);

    // Escaped in heading
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\section{Price is \\$5 \\& 10\\% off \\{today\\}}") != null);

    // Escaped in paragraph (notice textbackslash/textasciicircum/textasciitilde)
    try std.testing.expect(std.mem.indexOf(u8, tex, "Path A\\textbackslash{}B with \\#hash \\_under\\_ \\textasciicircum{}caret\\textasciitilde{}tilde") != null);

    // Code block raw
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\begin{verbatim}\nprintf(\"100% done\\n\"); // keep % and \\\n\\end{verbatim}") != null);
}

// NEW: empty blocks do not emit
test "latex_export: empty math/paragraph do not emit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    {
        var p = ASTNode.init(A, NodeType.Content);
        p.content = "   \n";
        try root.children.append(p);
    }
    {
        var m = ASTNode.init(A, NodeType.Math);
        m.content = "  \n";
        try root.children.append(m);
    }

    const tex = try exportAstToLatex(&root, A);
    defer A.free(tex);

    // Should be only a trailing newline
    try std.testing.expectEqual(@as(usize, 1), tex.len);
    try std.testing.expectEqual(@as(u8, '\n'), tex[0]);
}
