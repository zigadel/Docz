const std = @import("std");
const docz = @import("docz"); // public module root
const ASTNode = docz.AST.ASTNode;
const NodeType = docz.AST.NodeType;

// ─────────────────────────────────────────────────────────────
// Utilities
// ─────────────────────────────────────────────────────────────

const InlineStyleAttrs = struct {
    class_attr: ?[]const u8 = null,
    classes: ?[]const u8 = null,
    style: ?[]const u8 = null,
    name: ?[]const u8 = null,
};

fn isSpace(b: u8) bool {
    return b == ' ' or b == '\t' or b == '\r' or b == '\n';
}

fn eqLower(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        const aa = a[i];
        const bb = b[i];
        const la = if (aa >= 'A' and aa <= 'Z') aa + 32 else aa;
        const lb = if (bb >= 'A' and bb <= 'Z') bb + 32 else bb;
        if (la != lb) return false;
    }
    return true;
}
fn lowerAscii(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn escapeHtmlAttr(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    for (s) |ch| {
        switch (ch) {
            '&' => try out.appendSlice("&amp;"),
            '"' => try out.appendSlice("&quot;"),
            '<' => try out.appendSlice("&lt;"),
            '>' => try out.appendSlice("&gt;"),
            else => try out.append(ch),
        }
    }
    return out.toOwnedSlice();
}

/// Decode a handful of HTML entity forms that we expect to see inside already-escaped paragraph text.
fn decodeHtmlQuoteEntities(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < s.len) {
        if (std.mem.startsWith(u8, s[i..], "&quot;")) {
            try out.append('"');
            i += "&quot;".len;
            continue;
        }
        if (std.mem.startsWith(u8, s[i..], "&#34;")) {
            try out.append('"');
            i += "&#34;".len;
            continue;
        }
        try out.append(s[i]);
        i += 1;
    }
    return out.toOwnedSlice();
}

fn classLooksLikeCss(s: []const u8) bool {
    return std.mem.indexOfScalar(u8, s, ':') != null or std.mem.indexOfScalar(u8, s, '=') != null;
}

// ─────────────────────────────────────────────────────────────
// Head helpers
// ─────────────────────────────────────────────────────────────

fn writeHeadFromMeta(root: *const ASTNode, w: anytype) !void {
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
    for (root.children.items) |node| {
        if (node.node_type != .Import) continue;
        const href = node.attributes.get("href") orelse "";
        if (href.len != 0) {
            try w.print("<link rel=\"stylesheet\" href=\"{s}\">\n", .{href});
        }
    }
}

fn writeDefaultCssLink(root: *const ASTNode, w: anytype) !void {
    var href: []const u8 = "";
    var found = false;

    for (root.children.items) |node| {
        if (node.node_type != .Meta) continue;
        if (node.attributes.get("default_css")) |v| {
            href = v;
            found = true;
        }
    }

    if (found and href.len != 0) {
        try w.print("<link rel=\"stylesheet\" href=\"{s}\">\n", .{href});
    }
}

fn writeInlineCss(root: *const ASTNode, w: anytype) !void {
    var opened = false;
    for (root.children.items) |node| {
        if (node.node_type != .Css) continue;
        if (!opened) {
            try w.writeAll("<style>\n");
            opened = true;
        }
        if (node.content.len != 0) {
            try w.writeAll(node.content);
            try w.writeAll("\n");
        }
    }
    if (opened) try w.writeAll("</style>\n");
}

// ─────────────────────────────────────────────────────────────
// Style alias support
// ─────────────────────────────────────────────────────────────

fn buildStyleAliases(doc: *const ASTNode, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
    var out = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var itf = out.iterator();
        while (itf.next()) |e| {
            allocator.free(e.key_ptr.*);
            allocator.free(e.value_ptr.*);
        }
        out.deinit();
    }

    for (doc.children.items) |node| {
        if (node.node_type != .StyleDef) continue;

        var parsed = try node.parseStyleAliases(allocator);

        var it = parsed.iterator();
        while (it.next()) |e| {
            const alias = e.key_ptr.*;
            const classes = e.value_ptr.*;

            const gop = try out.getOrPut(try allocator.dupe(u8, alias));
            if (gop.found_existing) {
                allocator.free(gop.key_ptr.*); // drop duplicate insert key
                allocator.free(gop.value_ptr.*);
                gop.value_ptr.* = try allocator.dupe(u8, classes);
            } else {
                gop.value_ptr.* = try allocator.dupe(u8, classes);
            }
        }

        var itp = parsed.iterator();
        while (itp.next()) |e| {
            allocator.free(e.key_ptr.*);
            allocator.free(e.value_ptr.*);
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

// ─────────────────────────────────────────────────────────────
// Debug helpers (opt-in with @meta(debug_css="true"))
// ─────────────────────────────────────────────────────────────

fn metaFlag(root: *const ASTNode, key: []const u8) bool {
    for (root.children.items) |node| {
        if (node.node_type != .Meta) continue;
        if (node.attributes.get(key)) |v| {
            if (std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "1")) return true;
        }
    }
    return false;
}

fn collectImports(root: *const ASTNode, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (list.items) |s| allocator.free(s);
        list.deinit();
    }
    for (root.children.items) |node| {
        if (node.node_type != .Import) continue;
        if (node.attributes.get("href")) |href| {
            try list.append(try allocator.dupe(u8, href));
        }
    }
    return list;
}

fn mergeCss(root: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    for (root.children.items) |node| {
        if (node.node_type != .Css) continue;
        if (node.content.len != 0) {
            try buf.appendSlice(node.content);
            try buf.append('\n');
        }
    }
    return buf.toOwnedSlice();
}

fn writeDebugCssBanner(root: *const ASTNode, w: anytype, allocator: std.mem.Allocator) !void {
    if (!metaFlag(root, "debug_css")) return;

    try w.writeAll("<style>body{background:#fffbe6}</style>\n");

    var imports = try collectImports(root, allocator);
    defer {
        for (imports.items) |s| allocator.free(s);
        imports.deinit();
    }

    const css = try mergeCss(root, allocator);
    defer allocator.free(css);

    try w.writeAll(
        \\<div style="font:13px/1.4 system-ui, sans-serif; background:#fffbcc; color:#222; border-bottom:1px solid #e6db55; padding:10px; margin:0 0 10px 0">
        \\  <strong>Docz CSS Debug</strong><br>
        \\  Css blocks: 
    );

    var css_count: usize = 0;
    for (root.children.items) |node| {
        if (node.node_type == .Css) css_count += 1;
    }
    try w.print("{d}", .{css_count});

    try w.writeAll(" &middot; Imports: ");
    try w.print("{d}", .{imports.items.len});
    try w.writeAll("<br>\n");

    if (imports.items.len > 0) {
        try w.writeAll("  <div>Links:<ul style=\"margin:4px 0 0 18px\">");
        for (imports.items) |href| try w.print("<li><code>{s}</code></li>", .{href});
        try w.writeAll("</ul></div>\n");
    }

    const preview_len: usize = if (css.len > 800) 800 else css.len;
    try w.writeAll("  <div>Inline &lt;style&gt; preview:</div>\n");
    try w.writeAll("  <pre style=\"white-space:pre-wrap; background:#111; color:#eee; padding:8px; border-radius:6px; margin:6px 0 0 0\">");
    try w.writeAll(css[0..preview_len]);
    if (css.len > preview_len) try w.writeAll("\n…(truncated)...");
    try w.writeAll("</pre>\n</div>\n");
}

// ─────────────────────────────────────────────────────────────
// Inline @style(...)…@end rewriter (works in already-HTML-inline paragraphs)
// ─────────────────────────────────────────────────────────────

/// Parse inside "(...)" — tolerant to key="...", key:"...", spaces, and &quot;.
/// Only extracts: class/classes, style, name
fn parseInlineStyleAttrsAlloc(allocator: std.mem.Allocator, raw: []const u8) !InlineStyleAttrs {
    var attrs: InlineStyleAttrs = .{};

    // We decode entities into a temp buffer, *but we dupe any values we keep*
    const unquoted = try decodeHtmlQuoteEntities(allocator, raw);
    defer allocator.free(unquoted);

    var i: usize = 0;
    while (i < unquoted.len) {
        while (i < unquoted.len and (isSpace(unquoted[i]) or unquoted[i] == ',')) : (i += 1) {}
        if (i >= unquoted.len) break;

        const ks = i;
        while (i < unquoted.len) : (i += 1) {
            const ch = unquoted[i];
            if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-')) break;
        }
        const ke = i;
        if (ke == ks) {
            i += 1;
            continue;
        }
        const key = std.mem.trim(u8, unquoted[ks..ke], " \t\r\n");

        while (i < unquoted.len and isSpace(unquoted[i])) : (i += 1) {}
        if (i < unquoted.len and (unquoted[i] == '=' or unquoted[i] == ':')) i += 1;
        while (i < unquoted.len and isSpace(unquoted[i])) : (i += 1) {}

        var val: []const u8 = "";
        if (i < unquoted.len and unquoted[i] == '"') {
            i += 1;
            const vs = i;
            while (i < unquoted.len and unquoted[i] != '"') : (i += 1) {}
            const ve = if (i <= unquoted.len) i else unquoted.len;
            val = unquoted[vs..ve];
            if (i < unquoted.len and unquoted[i] == '"') i += 1;
        } else {
            const vs2 = i;
            while (i < unquoted.len and unquoted[i] != ',' and unquoted[i] != ')') : (i += 1) {}
            val = std.mem.trim(u8, unquoted[vs2..i], " \t\r\n");
        }

        // Duplicate val slices we keep so they survive past this function.
        if (eqLower(key, "class") or eqLower(key, "classes")) {
            const copy = try allocator.dupe(u8, val);
            attrs.class_attr = copy;
            attrs.classes = copy;
        } else if (eqLower(key, "style")) {
            attrs.style = try allocator.dupe(u8, val);
        } else if (eqLower(key, "name")) {
            attrs.name = try allocator.dupe(u8, val);
        }
    }

    return attrs;
}

fn freeInlineStyleAttrs(allocator: std.mem.Allocator, a: *InlineStyleAttrs) void {
    // Only free what we allocated in parseInlineStyleAttrsAlloc.
    // Note: class_attr and classes may alias the same buffer; free once.
    // We free via classes and null out both.
    if (a.classes) |buf| {
        allocator.free(buf);
        a.classes = null;
        a.class_attr = null;
    }
    if (a.style) |buf| {
        allocator.free(buf);
        a.style = null;
    }
    if (a.name) |buf| {
        allocator.free(buf);
        a.name = null;
    }
}

/// Rewrites all `@style(...) ... @end` inside a paragraph string.
/// Tolerates extra spaces: `@style (...)` and handles `&quot;` in attr list.
/// If malformed (missing `)` or `@end`), leaves the remainder untouched.
pub fn rewriteInlineStyleDirectives(
    allocator: std.mem.Allocator,
    s: []const u8,
    aliases: *const std.StringHashMap([]const u8),
) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    const open_tag = "@style(";
    const end_tag = "@end";

    while (i < s.len) {
        // Find next "@style("
        const at_opt = std.mem.indexOfPos(u8, s, i, open_tag);
        if (at_opt == null) {
            try out.appendSlice(s[i..]);
            break;
        }
        const at = at_opt.?;

        // Emit literal prefix
        try out.appendSlice(s[i..at]);

        // Parse "(...)"
        const attrs_start = at + open_tag.len;
        const close_paren_opt = std.mem.indexOfScalarPos(u8, s, attrs_start, ')');
        if (close_paren_opt == null) {
            // Malformed → emit rest literally
            try out.appendSlice(s[at..]);
            break;
        }
        const close_paren = close_paren_opt.?;
        const attrs_text = s[attrs_start..close_paren];

        // NOTE: must be 'var' so we can free() it later
        var attrs = try parseInlineStyleAttrsAlloc(allocator, attrs_text);
        defer freeInlineStyleAttrs(allocator, &attrs);

        // After ')', skip space then capture until "@end"
        var p = close_paren + 1;
        while (p < s.len and isSpace(s[p])) : (p += 1) {}
        const end_opt = std.mem.indexOfPos(u8, s, p, end_tag);
        if (end_opt == null) {
            // Malformed → emit rest literally
            try out.appendSlice(s[at..]);
            break;
        }
        const end_idx = end_opt.?;
        const inner = s[p..end_idx];

        // Render precedence: style= → class(es)=/class= → alias(name=) → fallback(class looks like CSS?)
        if (attrs.style) |sty_raw| {
            const sty = try escapeHtmlAttr(allocator, sty_raw);
            defer allocator.free(sty);

            try out.appendSlice("<span style=\"");
            try out.appendSlice(sty);
            try out.appendSlice("\">");
            try out.appendSlice(inner);
            try out.appendSlice("</span>");
        } else {
            var cls_choice: ?[]const u8 = null;

            if (attrs.classes) |cls_raw| {
                cls_choice = cls_raw; // owned by attrs
            } else if (attrs.name) |nm| {
                if (aliases.get(nm)) |resolved| {
                    cls_choice = resolved; // borrowed from aliases
                }
            } else if (attrs.class_attr) |maybe| {
                if (classLooksLikeCss(maybe)) {
                    const sty2 = try escapeHtmlAttr(allocator, maybe);
                    defer allocator.free(sty2);

                    try out.appendSlice("<span style=\"");
                    try out.appendSlice(sty2);
                    try out.appendSlice("\">");
                    try out.appendSlice(inner);
                    try out.appendSlice("</span>");

                    i = end_idx + end_tag.len;
                    continue;
                } else {
                    cls_choice = maybe; // treat as class list
                }
            }

            if (cls_choice) |cls_raw2| {
                const cls = try escapeHtmlAttr(allocator, cls_raw2);
                defer allocator.free(cls);

                try out.appendSlice("<span class=\"");
                try out.appendSlice(cls);
                try out.appendSlice("\">");
                try out.appendSlice(inner);
                try out.appendSlice("</span>");
            } else {
                // No usable attrs → drop wrapper
                try out.appendSlice(inner);
            }
        }

        // Advance past "@end"
        i = end_idx + end_tag.len;
    }

    return out.toOwnedSlice();
}

// ─────────────────────────────────────────────────────────────
// Body writer
// ─────────────────────────────────────────────────────────────

fn writeBodyFromAst(
    root: *const docz.AST.ASTNode,
    w: anytype,
    allocator: std.mem.Allocator,
    aliases: *const std.StringHashMap([]const u8),
) !void {
    for (root.children.items) |node| {
        switch (node.node_type) {
            .Meta => {},
            .Heading => {
                const level = node.attributes.get("level") orelse "1";
                const text = std.mem.trimRight(u8, node.content, " \t\r\n");
                try w.print("<h{s}>{s}</h{s}>\n", .{ level, text, level });
            },
            .Content => {
                const text = std.mem.trimRight(u8, node.content, " \t\r\n");
                if (text.len == 0) break;

                if (std.mem.indexOf(u8, text, "@style") != null) {
                    const rewritten = try rewriteInlineStyleDirectives(allocator, text, aliases);
                    defer allocator.free(rewritten);
                    try w.print("<p>{s}</p>\n", .{rewritten});
                } else {
                    try w.print("<p>{s}</p>\n", .{text});
                }
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
            .Import, .Css, .StyleDef => {},
            .Style => {
                const classes = resolveStyleClasses(&node, aliases);
                if (classes.len != 0) {
                    try w.print("<div class=\"{s}\">{s}</div>\n", .{ classes, node.content });
                } else {
                    try w.print("<div>{s}</div>\n", .{node.content});
                }
            },
            else => {
                try w.print("<!-- Unhandled node: {s} -->\n", .{@tagName(node.node_type)});
            },
        }
    }
}

// ─────────────────────────────────────────────────────────────
// Public helpers for CLI (CSS externalization path)
// ─────────────────────────────────────────────────────────────

pub fn collectInlineCss(root: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    for (root.children.items) |node| {
        if (node.node_type != .Css) continue;
        if (node.content.len != 0) {
            try buf.appendSlice(node.content);
            try buf.append('\n');
        }
    }
    return buf.toOwnedSlice();
}

pub fn stripFirstStyleBlock(html: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const open_tag_needle = "<style";
    const close_tag_needle = "</style>";

    const open_idx_opt = std.mem.indexOf(u8, html, open_tag_needle);
    if (open_idx_opt == null) {
        return try allocator.dupe(u8, html);
    }
    const open_idx = open_idx_opt.?;

    const gt_idx_opt = std.mem.indexOfScalarPos(u8, html, open_idx, '>');
    if (gt_idx_opt == null) {
        return try allocator.dupe(u8, html);
    }
    const open_gt = gt_idx_opt.? + 1;

    const close_idx_opt = std.mem.indexOfPos(u8, html, open_gt, close_tag_needle);
    if (close_idx_opt == null) {
        return try allocator.dupe(u8, html);
    }
    const close_idx = close_idx_opt.?;
    const close_end = close_idx + close_tag_needle.len;

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    try out.appendSlice(html[0..open_idx]);
    if (out.items.len > 0 and out.items[out.items.len - 1] == '\n') {
        _ = out.pop();
    }
    try out.appendSlice(html[close_end..]);

    return out.toOwnedSlice();
}

// ─────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────

pub fn exportHtml(doc: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const w = out.writer();

    var aliases = try buildStyleAliases(doc, allocator);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| {
            allocator.free(e.key_ptr.*);
            allocator.free(e.value_ptr.*);
        }
        aliases.deinit();
    }

    try w.writeAll("<!DOCTYPE html>\n<html>\n  <head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n");
    try writeHeadFromMeta(doc, w);
    try writeImports(doc, w);
    try writeDefaultCssLink(doc, w);
    try writeInlineCss(doc, w);
    try w.writeAll("  </head>\n  <body>\n");

    try writeDebugCssBanner(doc, w, allocator);
    try writeBodyFromAst(doc, w, allocator, &aliases);

    try w.writeAll("  </body>\n</html>\n");
    return out.toOwnedSlice();
}

// ─────────────────────────────────────────────────────────────
// Tests (focused on the inline @style rewrite)
// ─────────────────────────────────────────────────────────────

test "rewriteInlineStyleDirectives: class with HTML-escaped &quot;" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = std.StringHashMap([]const u8).init(A);
    defer aliases.deinit();

    const para =
        "The @style(class=&quot;color = red&quot;) preview @end server exposes...";
    const out = try rewriteInlineStyleDirectives(A, para, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "<span class=\"color = red\">preview </span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@style(") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@end") == null);
}

test "rewriteInlineStyleDirectives: style= + inner kept intact" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = std.StringHashMap([]const u8).init(A);
    defer aliases.deinit();

    const para =
        "A @style(style:\"font-weight:bold\") <em>word</em> @end here.";
    const out = try rewriteInlineStyleDirectives(A, para, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "<span style=\"font-weight:bold\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<em>word</em>") != null);
}

test "exportHtml integrates inline rewrite for Content node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    // Paragraph with inline directive (with &quot;)
    {
        var p = ASTNode.init(A, NodeType.Content);
        p.content = "The @style(class=&quot;color = red&quot;) preview @end server.";
        try root.children.append(p);
    }

    const html = try exportHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<p>The <span class=\"color = red\">preview </span> server.</p>") != null);
}
