const std = @import("std");

// This module is built as "html_export" (see build.zig) and is also re-exported
// by the public "docz" module. We import docz for AST types and the inline
// renderer pass.
const docz = @import("docz");
const utils_fs = @import("utils_fs"); // module name you wire in build.zig
const AST = docz.AST;
const ASTNode = AST.ASTNode;
const NodeType = AST.NodeType;

// Inline renderer facade (matches your root.zig: renderer.inline_.renderInline)
const Inline = docz.renderer.inline_;

// -----------------------------------------------------------------------------
// Small writer adapter for ArrayList(u8) on this Zig version
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// Small HTML escaper (used for <title> etc.)
// -----------------------------------------------------------------------------
fn escapeHtml(A: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(A);

    for (s) |ch| switch (ch) {
        '<' => try out.appendSlice(A, "&lt;"),
        '>' => try out.appendSlice(A, "&gt;"),
        '&' => try out.appendSlice(A, "&amp;"),
        '"' => try out.appendSlice(A, "&quot;"),
        '\'' => try out.appendSlice(A, "&#39;"),
        else => try out.append(A, ch),
    };
    return try out.toOwnedSlice(A);
}

// -----------------------------------------------------------------------------
// Style alias utilities (shared notion with inline renderer)
// -----------------------------------------------------------------------------
fn buildStyleAliases(doc: *const ASTNode, A: std.mem.Allocator) !std.StringHashMap([]const u8) {
    var out = std.StringHashMap([]const u8).init(A);
    errdefer {
        var itf = out.iterator();
        while (itf.next()) |e| {
            A.free(e.key_ptr.*);
            A.free(e.value_ptr.*);
        }
        out.deinit(); // no allocator param on this Zig
    }

    for (doc.children.items) |node| {
        if (node.node_type != .StyleDef) continue;

        var parsed = try node.parseStyleAliases(A);

        var it = parsed.iterator();
        while (it.next()) |e| {
            const alias = e.key_ptr.*;
            const classes = e.value_ptr.*;

            const gop = try out.getOrPut(try A.dupe(u8, alias));
            if (gop.found_existing) {
                A.free(gop.key_ptr.*);
                A.free(gop.value_ptr.*);
            }
            gop.value_ptr.* = try A.dupe(u8, classes);
        }

        var itp = parsed.iterator();
        while (itp.next()) |e| {
            A.free(e.key_ptr.*);
            A.free(e.value_ptr.*);
        }
        parsed.deinit();
    }

    return out;
}

fn resolveStyleClasses(style_node: *const ASTNode, aliases: *const std.StringHashMap([]const u8)) []const u8 {
    if (style_node.attributes.get("classes")) |cls| return cls;
    if (style_node.attributes.get("name")) |alias| {
        if (aliases.get(alias)) |resolved| return resolved;
    }
    return "";
}

// -----------------------------------------------------------------------------
// Title extraction
//   - prefer Heading level=1
//   - then Meta name=title / title=...
//   - fallback: "Docz"
// -----------------------------------------------------------------------------
fn extractTitle(doc: *const ASTNode) []const u8 {
    const candidate: []const u8 = "Docz";

    for (doc.children.items) |node| {
        switch (node.node_type) {
            .Heading => {
                if (node.attributes.get("level")) |lv| {
                    if (std.mem.eql(u8, lv, "1")) return node.content;
                }
            },
            .Meta => {
                if (node.attributes.get("title")) |t| return t;
                if (node.attributes.get("name")) |n| {
                    if (std.ascii.eqlIgnoreCase(n, "title")) {
                        if (node.attributes.get("content")) |c| return c;
                        return node.content;
                    }
                }
            },
            else => {},
        }
    }

    return candidate;
}

// -----------------------------------------------------------------------------
// Minimal HTML framing
// -----------------------------------------------------------------------------
fn writeHeadStart(w: anytype, title_text: []const u8, A: std.mem.Allocator) !void {
    const esc = try escapeHtml(A, title_text);
    defer A.free(esc);

    try w.writeAll(
        \\<!DOCTYPE html>
        \\<html>
        \\  <head>
        \\    <meta charset="utf-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1" />
        \\
    );
    try w.print("    <title>{s}</title>\n", .{esc});
    try w.writeAll("  </head>\n  <body>\n");
}

fn writeHeadEnd(w: anytype) !void {
    try w.writeAll(
        \\  </body>
        \\</html>
        \\
    );
}

// -----------------------------------------------------------------------------
// Body writer (delegates inline to Inline.renderInline)
// -----------------------------------------------------------------------------
fn writeBodyFromAst(
    root: *const ASTNode,
    w: anytype,
    A: std.mem.Allocator,
) !void {
    // build aliases once
    var aliases = try buildStyleAliases(root, A);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| {
            A.free(e.key_ptr.*);
            A.free(e.value_ptr.*);
        }
        aliases.deinit(); // no allocator param
    }

    for (root.children.items) |node| {
        switch (node.node_type) {
            .Meta => {}, // head/meta handled separately

            .Heading => {
                const level = node.attributes.get("level") orelse "1";
                const text = std.mem.trimRight(u8, node.content, " \t\r\n");
                try w.print("<h{s}>{s}</h{s}>\n", .{ level, text, level });
            },

            .Content => {
                const text = std.mem.trimRight(u8, node.content, " \t\r\n");
                if (text.len == 0) continue;

                // Inline rewrite pass (code spans, @(...)… forms, links, etc.)
                const inlined = try Inline.renderInline(A, text, &aliases);
                defer A.free(inlined);

                try w.print("<p>{s}</p>\n", .{inlined});
            },

            .CodeBlock => {
                try w.print("<pre><code>{s}</code></pre>\n", .{node.content});
            },

            .Math => {
                try w.print("<div class=\"math\">{s}</div>\n", .{node.content});
            },

            .Media => {
                const src = node.attributes.get("src") orelse "";
                if (src.len != 0) try w.print("<img src=\"{s}\" />\n", .{src});
            },

            .Style => {
                const classes = resolveStyleClasses(&node, &aliases);
                if (classes.len != 0)
                    try w.print("<div class=\"{s}\">{s}</div>\n", .{ classes, node.content })
                else
                    try w.print("<div>{s}</div>\n", .{node.content});
            },

            .Import, .Css, .StyleDef => {
                // handled by CLI/link-injection or separate head assembly
            },

            else => {
                try w.print("<!-- Unhandled node: {s} -->\n", .{@tagName(node.node_type)});
            },
        }
    }
}

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------
pub fn exportHtml(doc: *const ASTNode, A: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(A);

    var lw = ListWriter{ .list = &buf, .alloc = A };
    const w = &lw;

    const title_text = extractTitle(doc);
    try writeHeadStart(w, title_text, A);
    try writeHeadMeta(doc, w, A);
    if (shouldInjectDefaultStyles(doc)) {
        try writeDefaultStyleFloor(w);
    }
    try writeBodyFromAst(doc, w, A);
    try writeHeadEnd(w);

    return try buf.toOwnedSlice(A);
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/// Emit <meta ...> tags based on @meta(...) nodes in the AST.
/// Rules:
/// - Title is handled elsewhere; skip it here.
/// - If attributes contain ("name","content"), emit <meta name=".." content="..">
/// - If attributes contain "author", emit <meta name="author" content="..">
/// - If neither ("name","content") nor "author" is present but node.content is non-empty
///   and there's a "name", use node.content as the value.
fn writeHeadMeta(doc: *const ASTNode, w: anytype, A: std.mem.Allocator) !void {
    for (doc.children.items) |node| {
        if (node.node_type != .Meta) continue;

        // Do NOT early-continue if there's a title; just avoid emitting it here.
        // Title is handled by writeHeadStart().

        // 1) Explicit author
        if (node.attributes.get("author")) |author| {
            const esc_val = try escapeHtml(A, author);
            defer A.free(esc_val);
            try w.print("    <meta name=\"author\" content=\"{s}\">\n", .{esc_val});
        }

        // 2) Generic name/content
        if (node.attributes.get("name")) |n| {
            // skip title here (title handled separately)
            if (!std.ascii.eqlIgnoreCase(n, "title")) {
                if (node.attributes.get("content")) |c| {
                    const esc_n = try escapeHtml(A, n);
                    const esc_c = try escapeHtml(A, c);
                    defer {
                        A.free(esc_n);
                        A.free(esc_c);
                    }
                    try w.print("    <meta name=\"{s}\" content=\"{s}\">\n", .{ esc_n, esc_c });
                } else if (node.content.len != 0) {
                    const esc_n = try escapeHtml(A, n);
                    const esc_c = try escapeHtml(A, node.content);
                    defer {
                        A.free(esc_n);
                        A.free(esc_c);
                    }
                    try w.print("    <meta name=\"{s}\" content=\"{s}\">\n", .{ esc_n, esc_c });
                }
            }
        }
    }
}

fn shouldInjectDefaultStyles(doc: *const ASTNode) bool {
    // Local tiny helper: treat common strings as truthy
    const TRUTHY = struct {
        fn is(v: []const u8) bool {
            return std.ascii.eqlIgnoreCase(v, "true") or
                std.ascii.eqlIgnoreCase(v, "on") or
                std.ascii.eqlIgnoreCase(v, "1") or
                std.ascii.eqlIgnoreCase(v, "yes") or
                std.ascii.eqlIgnoreCase(v, "y");
        }
    };

    for (doc.children.items) |node| {
        if (node.node_type != .Meta) continue;

        // 1) Explicit ergonomic flag: @meta(default_styles:"true")
        if (node.attributes.get("default_styles")) |v| {
            if (TRUTHY.is(v)) return true;
        }
        // Common alias: @meta(enable_default_styles:"true")
        if (node.attributes.get("enable_default_styles")) |v| {
            if (TRUTHY.is(v)) return true;
        }

        // 2) HTML-ish pattern: @meta(name:"docz-default-styles", content:"on")
        if (node.attributes.get("name")) |n| {
            const is_default =
                std.ascii.eqlIgnoreCase(n, "docz-default-styles") or
                std.ascii.eqlIgnoreCase(n, "default-styles") or
                std.ascii.eqlIgnoreCase(n, "enable-default-styles");
            if (is_default) {
                const v = node.attributes.get("content") orelse node.content;
                if (v.len == 0) return true; // presence → on
                if (TRUTHY.is(v)) return true;
            }
        }
    }
    return false;
}

fn writeDefaultStylesHead(w: anytype) !void {
    // Prefer a reusable project stylesheet if present:
    //   docz/assets/css/docz.core.css  →  served at /docz/assets/css/docz.core.css
    if (utils_fs.Fs.exists("assets/css/docz.core.css") or utils_fs.Fs.exists("docz/assets/css/docz.core.css")) {
        if (utils_fs.Fs.exists("docz/assets/css/docz.core.css")) {
            try w.writeAll("    <link rel=\"stylesheet\" href=\"/docz/assets/css/docz.core.css\" data-docz=\"default-floor\" crossorigin=\"anonymous\">\n");
        } else {
            try w.writeAll("    <link rel=\"stylesheet\" href=\"/assets/css/docz.core.css\" data-docz=\"default-floor\" crossorigin=\"anonymous\">\n");
        }
        return;
    }

    // Fallback: inline tiny floor (unchanged)
    try w.writeAll(
        \\    <style data-docz="default-floor">
        \\      /* docz-default-floor */
        \\      :root { --docz-font: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji"; }
        \\      html { line-height: 1.5; }
        \\      body { margin: 2rem auto; max-width: 72ch; padding: 0 1rem; font-family: var(--docz-font); color: #111; background: #fff; }
        \\      h1,h2,h3,h4,h5,h6 { line-height: 1.25; margin: 1.5em 0 0.6em; font-weight: 700; }
        \\      h1 { font-size: 2.25rem; }  h2 { font-size: 1.75rem; }  h3 { font-size: 1.375rem; }
        \\      h4 { font-size: 1.125rem; } h5,h6 { font-size: 1rem; }
        \\      p { margin: 0.9em 0; }
        \\      a { color: #2563eb; text-decoration: none; }
        \\      a:hover { text-decoration: underline; }
        \\      code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace; font-size: 0.95em; background: #f6f8fa; padding: 0.15em 0.35em; border-radius: 4px; }
        \\      pre { background: #0b1020; color: #e6edf3; padding: 0.9rem 1rem; border-radius: 6px; overflow: auto; }
        \\      pre code { background: transparent; padding: 0; }
        \\      ul,ol { margin: 0.9em 0; padding-left: 1.5em; }
        \\      blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid #e5e7eb; color: #374151; }
        \\      .math { margin: 1em 0; }
        \\    </style>
        \\ 
    );
}

fn writeDefaultStyleFloor(w: anytype) !void {
    // Keep tiny & opinionated; users can override with their own CSS or Tailwind.
    try w.writeAll(
        \\    <style data-docz="default-floor">
        \\      /* docz-default-floor */
        \\      :root { --docz-font: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji"; }
        \\      html { line-height: 1.5; }
        \\      body { margin: 2rem auto; max-width: 72ch; padding: 0 1rem; font-family: var(--docz-font); color: #111; background: #fff; }
        \\      h1,h2,h3,h4,h5,h6 { line-height: 1.25; margin: 1.5em 0 0.6em; font-weight: 700; }
        \\      h1 { font-size: 2.25rem; }  h2 { font-size: 1.75rem; }  h3 { font-size: 1.375rem; }
        \\      h4 { font-size: 1.125rem; } h5,h6 { font-size: 1rem; }
        \\      p { margin: 0.9em 0; }
        \\      a { color: #2563eb; text-decoration: none; }
        \\      a:hover { text-decoration: underline; }
        \\      code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace; font-size: 0.95em; background: #f6f8fa; padding: 0.15em 0.35em; border-radius: 4px; }
        \\      pre { background: #0b1020; color: #e6edf3; padding: 0.9rem 1rem; border-radius: 6px; overflow: auto; }
        \\      pre code { background: transparent; padding: 0; }
        \\      ul,ol { margin: 0.9em 0; padding-left: 1.5em; }
        \\      blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid #e5e7eb; color: #374151; }
        \\      .math { margin: 1em 0; }
        \\    </style>
        \\ 
    );
}

// -----------------------------------------------------------------------------
// CSS helpers (string scanning)
// -----------------------------------------------------------------------------
pub fn collectInlineCss(html: []const u8, A: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(A);

    var i: usize = 0;
    while (i < html.len) {
        const open = std.mem.indexOfPos(u8, html, i, "<style");
        if (open == null) break;
        var j = open.?;
        const gt = std.mem.indexOfPos(u8, html, j, ">") orelse break;
        j = gt + 1;
        const close = std.mem.indexOfPos(u8, html, j, "</style>");
        if (close == null) break;

        try out.appendSlice(A, html[j..close.?]);
        try out.append(A, '\n');

        i = close.? + "</style>".len;
    }

    return try out.toOwnedSlice(A);
}

// Remove only the first <style>...</style> block from HTML and return the new
// string. If none found, returns a copy of the original.
pub fn stripFirstStyleBlock(html: []const u8, A: std.mem.Allocator) ![]u8 {
    const open = std.mem.indexOf(u8, html, "<style");
    if (open == null) return A.dupe(u8, html);
    const gt = std.mem.indexOfPos(u8, html, open.? + 1, ">") orelse return A.dupe(u8, html);
    const close = std.mem.indexOfPos(u8, html, gt + 1, "</style>") orelse return A.dupe(u8, html);

    var out = std.ArrayList(u8){};
    errdefer out.deinit(A);

    try out.appendSlice(A, html[0..open.?]);
    try out.appendSlice(A, html[close + "</style>".len ..]);

    return try out.toOwnedSlice(A);
}

// -----------------------------------------------------------------------------
// Tests (kept concise, no nested functions)
// -----------------------------------------------------------------------------
test "exportHtml: title extraction + heading renders text" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit(A);

    {
        var t = ASTNode.init(A, NodeType.Heading);
        try t.attributes.put("level", "1");
        t.content = "Integration Test";
        try root.children.append(A, t);
    }
    {
        var p = ASTNode.init(A, NodeType.Content);
        p.content = "Hello paragraph.";
        try root.children.append(A, p);
    }

    const html = try exportHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<title>Integration Test</title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Integration Test") != null);
}

test "exportHtml: paragraph delegates to inline renderer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit(A);

    {
        var p = ASTNode.init(A, NodeType.Content);
        p.content = "Visit [Zig](https://ziglang.org).";
        try root.children.append(A, p);
    }

    const html = try exportHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<a href=\"https://ziglang.org\">Zig</a>") != null);
}

test "css helpers: collect + strip first style block" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const html =
        \\<html><head>
        \\<style>/* one */ .a{}</style>
        \\<style>/* two */ .b{}</style>
        \\</head><body></body></html>
    ;

    const css = try collectInlineCss(html, A);
    defer A.free(css);
    try std.testing.expect(std.mem.indexOf(u8, css, "/* one */") != null);
    try std.testing.expect(std.mem.indexOf(u8, css, "/* two */") != null);

    const stripped = try stripFirstStyleBlock(html, A);
    defer A.free(stripped);
    try std.testing.expect(std.mem.indexOf(u8, stripped, "/* one */") == null);
    try std.testing.expect(std.mem.indexOf(u8, stripped, "/* two */") != null);
}

test "exportHtml: meta author appears in <head>" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit(A);

    {
        var m = ASTNode.init(A, NodeType.Meta);
        // typical @meta(title:"...", author:"...") mapping
        try m.attributes.put("title", "Docz Title");
        try m.attributes.put("author", "Docz Authors");
        try root.children.append(A, m);
    }
    {
        var h = ASTNode.init(A, NodeType.Heading);
        try h.attributes.put("level", "1");
        h.content = "Docz Title";
        try root.children.append(A, h);
    }

    const html = try exportHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<title>Docz Title</title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<meta name=\"author\" content=\"Docz Authors\">") != null);
}

test "exportHtml: opt-in default styles injects CSS floor" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit(A);

    // opt-in meta
    {
        var m = ASTNode.init(A, NodeType.Meta);
        try m.attributes.put("name", "docz-default-styles");
        try m.attributes.put("content", "on");
        try root.children.append(A, m);
    }
    // some content
    {
        var h = ASTNode.init(A, NodeType.Heading);
        try h.attributes.put("level", "1");
        h.content = "Hello";
        try root.children.append(A, h);
    }
    {
        var p = ASTNode.init(A, NodeType.Content);
        p.content = "This is **nice**.";
        try root.children.append(A, p);
    }

    const html = try exportHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "data-docz=\"default-floor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "/* docz-default-floor */") != null);
}
