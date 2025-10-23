const std = @import("std");

// Expose a simple AST surface via your public docz module
const docz = @import("docz");
const AST = docz.AST;
const ASTNode = AST.ASTNode;
const NodeType = AST.NodeType;

// -----------------------------------------------------------------------------
// Tiny buffer writer for Zig 0.16 (avoid std.io.Writer diffs)
// -----------------------------------------------------------------------------
const ListWriter = struct {
    list: *std.ArrayList(u8),
    alloc: std.mem.Allocator,

    fn writeAll(self: *ListWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.alloc, bytes);
    }

    fn print(self: *ListWriter, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.alloc, fmt, args);
        defer self.alloc.free(s);
        try self.list.appendSlice(self.alloc, s);
    }
};

// -----------------------------------------------------------------------------
// Minimal helpers
// -----------------------------------------------------------------------------
fn trimRight(s: []const u8) []const u8 {
    return std.mem.trimRight(u8, s, " \t\r\n");
}

fn emitMeta(w: *ListWriter, node: *const ASTNode) !void {
    // We only care about title / author for tests.
    if (node.attributes.get("title")) |t| {
        const v = trimRight(t);
        if (v.len != 0) try w.print("\\title{{{s}}}\n", .{v});
        return;
    }
    if (node.attributes.get("author")) |a| {
        const v = trimRight(a);
        if (v.len != 0) try w.print("\\author{{{s}}}\n", .{v});
        return;
    }
}

fn emitHeading(w: *ListWriter, node: *const ASTNode) !void {
    const level_str = node.attributes.get("level") orelse "1";
    const txt = trimRight(node.content);

    // Map: 1 -> \section, 2 -> \subsection, >=3 -> \subsubsection
    var cmd: []const u8 = "\\section";
    if (std.mem.eql(u8, level_str, "2")) cmd = "\\subsection" else if (!std.mem.eql(u8, level_str, "1")) cmd = "\\subsubsection";

    try w.print("{s}{{{s}}}\n\n", .{ cmd, txt });
}

fn emitParagraph(w: *ListWriter, node: *const ASTNode) !void {
    const t = trimRight(node.content);
    if (t.len == 0) return;
    try w.print("{s}\n\n", .{t});
}

fn emitCode(w: *ListWriter, node: *const ASTNode) !void {
    try w.writeAll("\\begin{verbatim}\n");
    try w.writeAll(node.content);
    // Ensure body ends with a single newline before the end tag
    if (node.content.len == 0 or node.content[node.content.len - 1] != '\n') {
        try w.writeAll("\n");
    }
    try w.writeAll("\\end{verbatim}\n\n");
}

fn emitMath(w: *ListWriter, node: *const ASTNode) !void {
    try w.writeAll("\\begin{equation}\n");
    try w.writeAll(trimRight(node.content));
    try w.writeAll("\n\\end{equation}\n\n");
}

fn emitImage(w: *ListWriter, node: *const ASTNode) !void {
    const src = node.attributes.get("src") orelse "";
    if (src.len == 0) return;
    try w.print("\\includegraphics{{{s}}}\n\n", .{src});
}

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------
pub fn exportAstToLatex(root: *const ASTNode, A: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(A);

    var lw = ListWriter{ .list = &out, .alloc = A };

    // Walk the top-level nodes in order and emit LaTeX fragments.
    for (root.children.items) |node| {
        switch (node.node_type) {
            .Meta => try emitMeta(&lw, &node),
            .Heading => try emitHeading(&lw, &node),
            .Content => try emitParagraph(&lw, &node),
            .CodeBlock => try emitCode(&lw, &node),
            .Math => try emitMath(&lw, &node),
            .Media => try emitImage(&lw, &node),

            // These are not part of the LaTeX export surface for the tests:
            .Import, .Css, .Style, .StyleDef => {},

            else => {}, // ignore anything unexpected
        }
    }

    // Ensure a single trailing newline exists (safe for normalizer in tests)
    if (out.items.len == 0 or out.items[out.items.len - 1] != '\n') {
        try out.append(A, '\n');
    }

    return try out.toOwnedSlice(A);
}

// -----------------------------------------------------------------------------
// Tiny smoke tests (local to this module)
// -----------------------------------------------------------------------------
test "latex export: basics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit(A);

    { // meta
        var m1 = ASTNode.init(A, NodeType.Meta);
        try m1.attributes.put("title", "Roundtrip Spec");
        try root.children.append(A, m1);

        var m2 = ASTNode.init(A, NodeType.Meta);
        try m2.attributes.put("author", "Docz");
        try root.children.append(A, m2);
    }
    { // heading + para
        var h = ASTNode.init(A, NodeType.Heading);
        try h.attributes.put("level", "1");
        h.content = "Intro";
        try root.children.append(A, h);

        var p = ASTNode.init(A, NodeType.Content);
        p.content = "Hello world paragraph.";
        try root.children.append(A, p);
    }
    { // code
        var c = ASTNode.init(A, NodeType.CodeBlock);
        c.content = "const x = 1;";
        try root.children.append(A, c);
    }
    { // math
        var m = ASTNode.init(A, NodeType.Math);
        m.content = "E = mc^2";
        try root.children.append(A, m);
    }
    { // image
        var img = ASTNode.init(A, NodeType.Media);
        try img.attributes.put("src", "img/logo.png");
        try root.children.append(A, img);
    }

    const tex = try exportAstToLatex(&root, A);
    defer A.free(tex);

    try std.testing.expect(std.mem.indexOf(u8, tex, "\\title{Roundtrip Spec}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\author{Docz}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\section{Intro}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "Hello world paragraph.\n\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\begin{verbatim}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\end{verbatim}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\begin{equation}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\end{equation}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\includegraphics{img/logo.png}") != null);
}
