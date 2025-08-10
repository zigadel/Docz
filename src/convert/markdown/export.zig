const std = @import("std");
const docz = @import("docz"); // <— instead of ../../parser/ast.zig
const ASTNode = docz.AST.ASTNode;
const NodeType = docz.AST.NodeType;

// -------------------------
// Helpers
// -------------------------

fn stripSingleTrailingNewline(buf: *std.ArrayList(u8)) void {
    if (buf.items.len != 0 and buf.items[buf.items.len - 1] == '\n') {
        _ = buf.pop();
    }
}

fn writeNewline(w: anytype) !void {
    try w.writeAll("\n");
}

fn writeBlankLine(w: anytype) !void {
    try w.writeAll("\n\n");
}

fn clampHeadingLevel(raw: usize) usize {
    return if (raw == 0) 1 else if (raw > 6) 6 else raw;
}

fn repeatChar(w: anytype, c: u8, n: usize) !void {
    var i: usize = 0;
    while (i < n) : (i += 1) try w.writeByte(c);
}

fn writeHeading(w: anytype, level_str: []const u8, text: []const u8) !void {
    const raw_level = std.fmt.parseUnsigned(usize, level_str, 10) catch 1;
    const lvl = clampHeadingLevel(raw_level);
    try repeatChar(w, '#', lvl);
    try w.writeByte(' ');
    try w.writeAll(text);
    try writeBlankLine(w);
}

fn writeParagraph(w: anytype, text: []const u8) !void {
    const t = std.mem.trim(u8, text, " \t\r\n");
    if (t.len == 0) return;
    try w.writeAll(t);
    try writeBlankLine(w);
}

/// Pick a fence for code blocks. If the body contains any backticks,
/// switch to tildes to avoid the need for escaping.
fn chooseFence(body: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, body, '`') != null) "~~~" else "```";
}

fn writeCodeBlock(w: anytype, lang_opt: ?[]const u8, body: []const u8) !void {
    const fence = chooseFence(body);
    try w.writeAll(fence);
    if (lang_opt) |lang| {
        if (lang.len > 0) {
            try w.writeByte(' ');
            try w.writeAll(lang);
        }
    }
    try writeNewline(w);
    try w.writeAll(body);
    try writeNewline(w);
    try w.writeAll(fence);
    try writeBlankLine(w);
}

fn writeMathBlock(w: anytype, body: []const u8) !void {
    // Block math as $$ ... $$
    try w.writeAll("$$\n");
    try w.writeAll(body);
    try w.writeAll("\n$$");
    try writeBlankLine(w);
}

fn writeImage(w: anytype, src: []const u8) !void {
    const s = std.mem.trim(u8, src, " \t\r\n");
    if (s.len == 0) return;
    try w.writeAll("![image](");
    try w.writeAll(s);
    try w.writeByte(')');
    try writeBlankLine(w);
}

// -------------------------
// Export API
// -------------------------

/// Export AST → GitHub-flavored Markdown (minimal).
/// - Meta(title) becomes a top-level `# Title`
/// - Headings map to `#`, `##`, ...
/// - Content becomes paragraphs
/// - CodeBlock uses fences; language goes after a space: "``` zig\n"
///   If body contains backticks, fence switches to `~~~`.
/// - Math is emitted inline as `$...$` on its own paragraph
/// - Media (src) becomes `![](<src>)`
pub fn exportAstToMarkdown(doc: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const w = out.writer();

    var last_was_code = false;

    for (doc.children.items) |node| {
        switch (node.node_type) {
            .Meta => {
                if (node.attributes.get("title")) |title| {
                    try w.print("# {s}\n", .{title});
                    const s = out.items;
                    if (!std.mem.endsWith(u8, s, "\n\n")) {
                        if (std.mem.endsWith(u8, s, "\n")) try out.append('\n') else try out.appendSlice("\n\n");
                    }
                    last_was_code = false;
                }
            },
            .Heading => {
                const level_str = node.attributes.get("level") orelse "1";
                var lvl: u8 = 1;
                if (level_str.len > 0 and level_str[0] >= '1' and level_str[0] <= '6')
                    lvl = @intCast(level_str[0] - '0');
                if (lvl < 1) lvl = 1;
                if (lvl > 6) lvl = 6;

                var i: usize = 0;
                while (i < lvl) : (i += 1) try w.print("#", .{});
                try w.print(" {s}\n", .{std.mem.trimRight(u8, node.content, " \t\r\n")});

                const s = out.items;
                if (!std.mem.endsWith(u8, s, "\n\n")) {
                    if (std.mem.endsWith(u8, s, "\n")) try out.append('\n') else try out.appendSlice("\n\n");
                }
                last_was_code = false;
            },
            .Content => {
                const txt = std.mem.trimRight(u8, node.content, " \t\r\n");
                if (txt.len != 0) {
                    try w.print("{s}\n", .{txt});
                    const s = out.items;
                    if (!std.mem.endsWith(u8, s, "\n\n")) {
                        if (std.mem.endsWith(u8, s, "\n")) try out.append('\n') else try out.appendSlice("\n\n");
                    }
                    last_was_code = false;
                }
            },
            .CodeBlock => {
                const lang = node.attributes.get("language") orelse "";
                const use_tildes = std.mem.indexOf(u8, node.content, "```") != null;
                const fence = if (use_tildes) "~~~" else "```";

                if (lang.len != 0) {
                    try w.print("{s} {s}\n{s}\n{s}\n", .{ fence, lang, node.content, fence });
                } else {
                    try w.print("{s}\n{s}\n{s}\n", .{ fence, node.content, fence });
                }

                // Ensure blank line after block
                const s = out.items;
                if (!std.mem.endsWith(u8, s, "\n\n")) {
                    if (std.mem.endsWith(u8, s, "\n")) try out.append('\n') else try out.appendSlice("\n\n");
                }
                last_was_code = true;
            },
            .Math => {
                // Keep $$...$$ blocks (tests look for this form)
                try w.print("$$\n{s}\n$$\n", .{node.content});

                // Ensure blank line after block
                const s = out.items;
                if (!std.mem.endsWith(u8, s, "\n\n")) {
                    if (std.mem.endsWith(u8, s, "\n")) try out.append('\n') else try out.appendSlice("\n\n");
                }
                last_was_code = false;
            },
            .Media => {
                const src = node.attributes.get("src") orelse "";
                if (src.len != 0) {
                    const alt = node.attributes.get("alt") orelse "image";
                    try w.print("![{s}]({s})\n", .{ alt, src });

                    const s = out.items;
                    if (!std.mem.endsWith(u8, s, "\n\n")) {
                        if (std.mem.endsWith(u8, s, "\n")) try out.append('\n') else try out.appendSlice("\n\n");
                    }
                    last_was_code = false;
                }
            },
            .Import, .Style => {},
            else => {},
        }
    }

    // EOF normalization
    if (out.items.len > 0) {
        if (std.mem.endsWith(u8, out.items, "\n\n")) {
            if (!last_was_code) {
                _ = out.pop(); // collapse to single newline if last block wasn’t code
            }
        } else if (!std.mem.endsWith(u8, out.items, "\n")) {
            try out.append('\n');
        }
    }

    return out.toOwnedSlice();
}

// -------------------------
// Unit tests
// -------------------------

test "markdown export: title meta + headings + paragraph" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    // Meta title
    {
        var meta = ASTNode.init(A, NodeType.Meta);
        try meta.attributes.put("title", "My Doc");
        try root.children.append(meta);
    }
    // H2
    {
        var h = ASTNode.init(A, NodeType.Heading);
        try h.attributes.put("level", "2");
        h.content = "Section";
        try root.children.append(h);
    }
    // Paragraph
    {
        var p = ASTNode.init(A, NodeType.Content);
        p.content = "Hello **world**!";
        try root.children.append(p);
    }

    const md = try exportAstToMarkdown(&root, A);
    defer A.free(md);

    const expected =
        \\# My Doc
        \\
        \\## Section
        \\
        \\Hello **world**!
        \\
    ;
    try std.testing.expectEqualStrings(expected, md);
}

test "markdown export: code, math, image, and spacing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    // Code block with language
    {
        var code = ASTNode.init(A, NodeType.CodeBlock);
        try code.attributes.put("language", "zig");
        code.content =
            \\const x: u8 = 42;
        ;
        try root.children.append(code);
    }

    // Math block
    {
        var math = ASTNode.init(A, NodeType.Math);
        math.content = "E = mc^2";
        try root.children.append(math);
    }

    // Image
    {
        var img = ASTNode.init(A, NodeType.Media);
        try img.attributes.put("src", "/img/logo.png");
        try root.children.append(img);
    }

    const md = try exportAstToMarkdown(&root, A);
    defer A.free(md);

    const snippet_code =
        \\``` zig
        \\const x: u8 = 42;
        \\```
    ;
    try std.testing.expect(std.mem.indexOf(u8, md, snippet_code) != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "$$\nE = mc^2\n$$") != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "![image](/img/logo.png)") != null);
}

test "markdown export: fence selection switches to tildes when body contains backticks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    var code = ASTNode.init(A, NodeType.CodeBlock);
    try code.attributes.put("language", "txt");
    code.content =
        \\here are three backticks: ```
        \\and more text
    ;
    try root.children.append(code);

    const md = try exportAstToMarkdown(&root, A);
    defer A.free(md);

    // Should use ~~~ fences
    try std.testing.expect(std.mem.indexOf(u8, md, "~~~ txt\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "\n~~~\n\n") != null);
}
