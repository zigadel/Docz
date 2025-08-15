const std = @import("std");
const docz = @import("docz"); // public module root
const ASTNode = docz.AST.ASTNode;
const NodeType = docz.AST.NodeType;

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
    // Minimal: only link rel=stylesheet for Import nodes (href)
    for (root.children.items) |node| {
        if (node.node_type != .Import) continue;
        const href = node.attributes.get("href") orelse "";
        if (href.len != 0) {
            try w.print("<link rel=\"stylesheet\" href=\"{s}\">\n", .{href});
        }
    }
}

/// Optional baseline stylesheet:
/// If any Meta node contains key "default_css", insert
///   <link rel="stylesheet" href="...">
/// Example in .dcz:
///   @meta(default_css="/_docz/default.css") @end
fn writeDefaultCssLink(root: *const ASTNode, w: anytype) !void {
    var href: []const u8 = "";
    var found = false;

    // Last-write-wins across Meta nodes
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

/// Merge all Css node bodies into a single <style>…</style> in <head>.
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

/// Build a single alias map from all StyleDef nodes (last write wins).
fn buildStyleAliases(doc: *const ASTNode, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
    // Output map: owns both keys and values.
    var out = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var itf = out.iterator();
        while (itf.next()) |e| {
            allocator.free(e.key_ptr.*);
            allocator.free(e.value_ptr.*);
        }
        out.deinit();
    }

    // Walk document once, merging all StyleDef blocks.
    for (doc.children.items) |node| {
        if (node.node_type != .StyleDef) continue;

        // Temporary parsed aliases: also owns its keys/values.
        var parsed = try node.parseStyleAliases(allocator);

        // Duplicate into `out`, then free `parsed` entries.
        var it = parsed.iterator();
        while (it.next()) |e| {
            const alias = e.key_ptr.*;
            const classes = e.value_ptr.*;

            // Insert/replace into `out` (duplicate to make ownership explicit).
            const gop = try out.getOrPut(try allocator.dupe(u8, alias));
            if (gop.found_existing) {
                // Free the newly allocated probe key; keep existing key
                allocator.free(gop.key_ptr.*);
                // Replace value
                allocator.free(gop.value_ptr.*);
                gop.value_ptr.* = try allocator.dupe(u8, classes);
            } else {
                gop.value_ptr.* = try allocator.dupe(u8, classes);
            }
        }

        // Free all entries owned by `parsed`, then drop the map struct.
        var itp = parsed.iterator();
        while (itp.next()) |e| {
            allocator.free(e.key_ptr.*);
            allocator.free(e.value_ptr.*);
        }
        parsed.deinit();
    }

    return out;
}

/// Resolve classes for a Style node: prefer explicit classes=, else lookup name= in alias map.
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

/// Visible debug box at top of <body> showing what we emitted into <head>.
fn writeDebugCssBanner(root: *const ASTNode, w: anytype, allocator: std.mem.Allocator) !void {
    if (!metaFlag(root, "debug_css")) return;

    // Obvious style so you can *see* head CSS applied
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

    // Show a preview of CSS (truncated)
    const preview_len = if (css.len > 800) 800 else css.len;
    try w.writeAll("  <div>Inline &lt;style&gt; preview:</div>\n");
    try w.writeAll("  <pre style=\"white-space:pre-wrap; background:#111; color:#eee; padding:8px; border-radius:6px; margin:6px 0 0 0\">");
    try w.writeAll(css[0..preview_len]);
    if (css.len > preview_len) try w.writeAll("\n…(truncated)...");
    try w.writeAll("</pre>\n</div>\n");
}

// ─────────────────────────────────────────────────────────────
// Body writer
// ─────────────────────────────────────────────────────────────

fn writeBodyFromAst(root: *const ASTNode, w: anytype, aliases: *const std.StringHashMap([]const u8)) !void {
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
            .Import, .Css, .StyleDef => {
                // handled in head or pre-pass; no body output
            },
            .Style => {
                const classes = resolveStyleClasses(&node, aliases);
                if (classes.len != 0) {
                    try w.print("<div class=\"{s}\">{s}</div>\n", .{ classes, node.content });
                } else {
                    // No classes resolved; output a plain wrapper for forward-compat.
                    try w.print("<div>{s}</div>\n", .{node.content});
                }
            },
            .Unknown => {
                try w.writeAll("<!-- Unhandled node: Unknown -->\n");
            },
            else => {
                // leave a comment for any future node types
                try w.print("<!-- Unhandled node: {s} -->\n", .{@tagName(node.node_type)});
            },
        }
    }
}

// ─────────────────────────────────────────────────────────────
// Public helpers for CLI (CSS externalization path)
// ─────────────────────────────────────────────────────────────

/// Collect the concatenated contents of all Css nodes in document order.
/// Returns a newly-allocated buffer (caller frees).
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

/// Remove the *first* <style ...>...</style> block from `html`.
/// If none found, returns a duplicate of `html`.
/// Robust to attributes on <style>, e.g. <style media="all">.
pub fn stripFirstStyleBlock(html: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const open_tag_needle = "<style";
    const close_tag_needle = "</style>";

    const open_idx_opt = std.mem.indexOf(u8, html, open_tag_needle);
    if (open_idx_opt == null) {
        // nothing to strip; return a copy
        return try allocator.dupe(u8, html);
    }
    const open_idx = open_idx_opt.?;

    // find end of opening tag '>'
    const gt_idx_opt = std.mem.indexOfScalarPos(u8, html, open_idx, '>');
    if (gt_idx_opt == null) {
        // malformed; be conservative and return original
        return try allocator.dupe(u8, html);
    }
    const open_gt = gt_idx_opt.? + 1; // first byte after '>'

    // find the corresponding closing tag
    const close_idx_opt = std.mem.indexOfPos(u8, html, open_gt, close_tag_needle);
    if (close_idx_opt == null) {
        // malformed; return original
        return try allocator.dupe(u8, html);
    }
    const close_idx = close_idx_opt.?;
    const close_end = close_idx + close_tag_needle.len;

    // Build result = html[0..open_idx] ++ html[close_end..]
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    try out.appendSlice(html[0..open_idx]);

    // Optionally trim one trailing newline right before <style> to keep tidy formatting.
    if (out.items.len > 0 and out.items[out.items.len - 1] == '\n') {
        _ = out.pop();
    }

    try out.appendSlice(html[close_end..]);

    return out.toOwnedSlice();
}

// ─────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────

/// Export AST -> minimal HTML5 document with head assets:
/// - Meta → <title>/<meta>
/// - Import(href) → <link rel="stylesheet" …>
/// - Css blocks → merged <style>…</style>
/// - StyleDef → alias map; Style(name|classes) → <div class="…">…</div>
/// - Optional default_css (from @meta) → <link rel="stylesheet" href="…">
pub fn exportHtml(doc: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const w = out.writer();

    // Build aliases once (cheap map; freed at end).
    var aliases = try buildStyleAliases(doc, allocator);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| {
            allocator.free(e.key_ptr.*);
            allocator.free(e.value_ptr.*);
        }
        aliases.deinit();
    }

    try w.writeAll("<!DOCTYPE html>\n<html>\n<head>\n");
    try writeHeadFromMeta(doc, w);
    try writeImports(doc, w);
    try writeDefaultCssLink(doc, w); // optional baseline CSS via @meta(default_css="…")
    try writeInlineCss(doc, w);
    try w.writeAll("</head>\n<body>\n");

    // Debug overlay (only if @meta(debug_css="true"))
    try writeDebugCssBanner(doc, w, allocator);

    try writeBodyFromAst(doc, w, &aliases);

    try w.writeAll("</body>\n</html>\n");
    return out.toOwnedSlice();
}

// ─────────────────────────────────────────────────────────────
// Unit tests
// ─────────────────────────────────────────────────────────────

test "html_export: emits title/meta/import/css and basic body" {
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
    // Css (inline)
    {
        var css = ASTNode.init(A, NodeType.Css);
        css.content = ".card{border:1px solid #ccc}";
        try root.children.append(css);
    }
    // Body: heading, para
    {
        var h = ASTNode.init(A, NodeType.Heading);
        try h.attributes.put("level", "1");
        h.content = "Welcome";
        try root.children.append(h);

        var p = ASTNode.init(A, NodeType.Content);
        p.content = "First paragraph.";
        try root.children.append(p);
    }

    const html = try exportHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<title>Hello</title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<meta name=\"author\" content=\"Docz Team\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<link rel=\"stylesheet\" href=\"/styles/site.css\">") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<style>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, ".card{border:1px solid #ccc}") != null);

    try std.testing.expect(std.mem.indexOf(u8, html, "<h1>Welcome</h1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<p>First paragraph.</p>") != null);
}

test "html_export: StyleDef + Style(name) expansion" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    // Define aliases
    {
        var def = ASTNode.init(A, NodeType.StyleDef);
        def.content =
            \\heading-1: h1-xl h1-weight
            \\body-text: prose max-w-none
        ;
        try root.children.append(def);
    }
    // Use alias via name=
    {
        var s = ASTNode.init(A, NodeType.Style);
        try s.attributes.put("name", "heading-1");
        s.content = "Title";
        try root.children.append(s);
    }
    // Direct classes=
    {
        var s2 = ASTNode.init(A, NodeType.Style);
        try s2.attributes.put("classes", "text-lg font-bold");
        s2.content = "Bold";
        try root.children.append(s2);
    }

    const html = try exportHtml(&root, A);
    defer A.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<div class=\"h1-xl h1-weight\">Title</div>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<div class=\"text-lg font-bold\">Bold</div>") != null);
}

test "html_export: head assets stay in <head>, not body" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    var def = ASTNode.init(A, NodeType.StyleDef);
    def.content = "a: b";
    try root.children.append(def);

    var css = ASTNode.init(A, NodeType.Css);
    css.content = ".x{y:z}";
    try root.children.append(css);

    var imp = ASTNode.init(A, NodeType.Import);
    try imp.attributes.put("href", "/a.css");
    try root.children.append(imp);

    const html = try exportHtml(&root, A);
    defer A.free(html);

    // We should have a </head> boundary.
    const head_end_opt = std.mem.indexOf(u8, html, "</head>");
    try std.testing.expect(head_end_opt != null);
    const head_end = head_end_opt.?;

    // CSS content must exist, but only before </head>.
    const css_pos_opt = std.mem.indexOf(u8, html, ".x{y:z}");
    try std.testing.expect(css_pos_opt != null);
    try std.testing.expect(css_pos_opt.? < head_end);

    // And that CSS must not appear in the body slice.
    const body_slice = html[head_end..];
    try std.testing.expect(std.mem.indexOf(u8, body_slice, ".x{y:z}") == null);

    // StyleDef raw text should not appear anywhere (it's meta, not emitted).
    try std.testing.expect(std.mem.indexOf(u8, html, "a: b") == null);

    // Import should be present in head as a link.
    try std.testing.expect(std.mem.indexOf(u8, html, "<link rel=\"stylesheet\" href=\"/a.css\">") != null);
}

test "collectInlineCss joins Css nodes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, NodeType.Document);
    defer root.deinit();

    var c1 = ASTNode.init(A, NodeType.Css);
    c1.content = "a{color:red}";
    try root.children.append(c1);

    var c2 = ASTNode.init(A, NodeType.Css);
    c2.content = "b{font-weight:bold}";
    try root.children.append(c2);

    const css = try collectInlineCss(&root, A);
    defer A.free(css);

    try std.testing.expect(std.mem.indexOf(u8, css, "a{color:red}\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, css, "b{font-weight:bold}\n") != null);
}

test "stripFirstStyleBlock removes the first <style>...</style>" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const html =
        \\<head>
        \\<style>
        \\body{margin:0}
        \\</style>
        \\<style id="second">h1{font-weight:700}</style>
        \\</head>
    ;
    const out = try stripFirstStyleBlock(html, A);
    defer A.free(out);

    // first style removed
    try std.testing.expect(std.mem.indexOf(u8, out, "body{margin:0}") == null);
    // second remains
    try std.testing.expect(std.mem.indexOf(u8, out, "h1{font-weight:700}") != null);
}
