const std = @import("std");
const docz = @import("docz");

const ASTNode = docz.AST.ASTNode;

// ─────────────────────────────────────────────────────────────
// Small writer for ArrayList(u8) compatible with this Zig build
// ─────────────────────────────────────────────────────────────
const ListWriter = struct {
    list: *std.ArrayList(u8),
    alloc: std.mem.Allocator,

    pub fn writeAll(self: *ListWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.alloc, bytes);
    }

    pub fn print(self: *ListWriter, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.alloc, fmt, args);
        defer self.alloc.free(s);
        try self.list.appendSlice(self.alloc, s);
    }
};

// ─────────────────────────────────────────────────────────────
// Minimal Markdown escaper (keep it conservative/on-demand)
// ─────────────────────────────────────────────────────────────
fn escapeInlineMd(A: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(A);

    for (s) |ch| switch (ch) {
        // escape characters that commonly flip formatting in inline text
        '*', '_', '`', '~', '\\' => {
            try out.append(A, '\\');
            try out.append(A, ch);
        },
        else => try out.append(A, ch),
    };

    return try out.toOwnedSlice(A);
}

// ─────────────────────────────────────────────────────────────
// Block helpers
// ─────────────────────────────────────────────────────────────
fn clampHeadingLevel(raw: []const u8) usize {
    const n = std.fmt.parseInt(usize, raw, 10) catch 1;
    if (n == 0) return 1;
    if (n > 6) return 6;
    return n;
}

fn writeHeading(w: *ListWriter, node: *const ASTNode, A: std.mem.Allocator) !void {
    const level = clampHeadingLevel(node.attributes.get("level") orelse "1");

    var hashes_buf: [6]u8 = .{ '#', '#', '#', '#', '#', '#' };
    const text = std.mem.trimRight(u8, node.content, " \t\r\n");
    const esc = try escapeInlineMd(A, text);
    defer A.free(esc);

    try w.writeAll(hashes_buf[0..level]);
    try w.print(" {s}\n\n", .{esc});
}

fn writeParagraph(w: *ListWriter, node: *const ASTNode, A: std.mem.Allocator) !void {
    const text = std.mem.trimRight(u8, node.content, " \t\r\n");
    if (text.len == 0) return;
    const esc = try escapeInlineMd(A, text);
    defer A.free(esc);
    try w.print("{s}\n\n", .{esc});
}

fn writeCodeBlock(w: *ListWriter, node: *const ASTNode) !void {
    const lang = node.attributes.get("language") orelse
        (node.attributes.get("lang") orelse "");
    try w.print("```{s}\n{s}\n```\n\n", .{ lang, node.content });
}

fn writeMath(w: *ListWriter, node: *const ASTNode) !void {
    // Keep simple & portable: fenced display math
    try w.print("$$\n{s}\n$$\n\n", .{node.content});
}

fn writeMedia(w: *ListWriter, node: *const ASTNode, A: std.mem.Allocator) !void {
    const src = node.attributes.get("src") orelse "";
    if (src.len == 0) return;

    // Try to use alt text if present; otherwise a placeholder
    const alt = node.attributes.get("alt") orelse "image";

    const esc_alt = try escapeInlineMd(A, alt);
    defer A.free(esc_alt);

    // URLs usually safe; don’t escape by default
    try w.print("![{s}]({s})\n\n", .{ esc_alt, src });
}

// ─────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────

/// Primary Markdown export function.
pub fn exportMarkdown(root: *const ASTNode, A: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(A);

    var w = ListWriter{ .list = &out, .alloc = A };

    // Walk top-level nodes in order and emit Markdown
    for (root.children.items) |node| {
        switch (node.node_type) {
            .Heading => try writeHeading(&w, &node, A),
            .Content => try writeParagraph(&w, &node, A),
            .CodeBlock => try writeCodeBlock(&w, &node),
            .Math => try writeMath(&w, &node),
            .Media => try writeMedia(&w, &node, A),

            // Skip head/alias/import blocks in .md output
            .Meta, .Css, .Style, .StyleDef, .Import => {},

            // Other node kinds: ignore (forward-compat)
            else => {},
        }
    }

    return try out.toOwnedSlice(A);
}

/// Back-compat name used by the CLI (`convert.zig`).
pub fn exportAstToMarkdown(root: *const ASTNode, A: std.mem.Allocator) ![]u8 {
    return exportMarkdown(root, A);
}

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────
test "markdown: headings, paragraph, code" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var doc = ASTNode.init(A, .Document);
    defer doc.deinit(A);

    {
        var h = ASTNode.init(A, .Heading);
        try h.attributes.put("level", "2");
        h.content = "Hello *Docz*";
        try doc.children.append(A, h);
    }
    {
        var p = ASTNode.init(A, .Content);
        p.content = "Some paragraph with `inline`.";
        try doc.children.append(A, p);
    }
    {
        var c = ASTNode.init(A, .CodeBlock);
        try c.attributes.put("language", "zig");
        c.content = "const x: u8 = 42;";
        try doc.children.append(A, c);
    }

    const md = try exportMarkdown(&doc, A);
    defer A.free(md);

    try std.testing.expect(std.mem.containsAtLeast(u8, md, 1, "## Hello \\*Docz\\*"));
    try std.testing.expect(std.mem.containsAtLeast(u8, md, 1, "Some paragraph with \\`inline\\`."));
    try std.testing.expect(std.mem.containsAtLeast(u8, md, 1, "```zig"));
    try std.testing.expect(std.mem.containsAtLeast(u8, md, 1, "const x: u8 = 42;"));
}
