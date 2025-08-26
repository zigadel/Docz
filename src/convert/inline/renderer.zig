// src/convert/inline/renderer.zig
const std = @import("std");

pub const StringMap = std.StringHashMap([]const u8);

pub const InlineStyleAttrs = struct {
    // Parsed attributes (all optional)
    name: ?[]const u8 = null, // alias key into StyleDef map
    classes: ?[]const u8 = null, // explicit classes
    style: ?[]const u8 = null, // explicit inline CSS
    class_attr: ?[]const u8 = null, // raw 'class=' value (may be classes or actually CSS mistaken as class)
};

fn isSpace(b: u8) bool {
    return b == ' ' or b == '\t' or b == '\r' or b == '\n';
}

fn asciiEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var idx: usize = 0;
    while (idx < a.len) : (idx += 1) {
        const ca = a[idx];
        const cb = b[idx];
        const la = if (ca >= 'A' and ca <= 'Z') ca + 32 else ca;
        const lb = if (cb >= 'A' and cb <= 'Z') cb + 32 else cb;
        if (la != lb) return false;
    }
    return true;
}

fn classLooksLikeCss(s: []const u8) bool {
    // crude heuristic: if there's a ':' earlier than a space or dot or end, it's probably CSS "color:red"
    return std.mem.indexOfScalar(u8, s, ':') != null and std.mem.indexOfScalar(u8, s, ';') != null;
}

fn htmlNeedsEscape(c: u8) bool {
    return c == '&' or c == '<' or c == '>';
}

fn htmlAttrNeedsEscape(c: u8) bool {
    return c == '&' or c == '<' or c == '>' or c == '"';
}

/// Escape text for HTML element content.
pub fn escapeHtml(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (!htmlNeedsEscape(ch)) {
            try out.append(ch);
            continue;
        }
        switch (ch) {
            '&' => try out.appendSlice("&amp;"),
            '<' => try out.appendSlice("&lt;"),
            '>' => try out.appendSlice("&gt;"),
            else => try out.append(ch),
        }
    }
    return out.toOwnedSlice();
}

/// Escape text for HTML attribute value (double-quoted).
fn escapeHtmlAttr(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (!htmlAttrNeedsEscape(ch)) {
            try out.append(ch);
            continue;
        }
        switch (ch) {
            '&' => try out.appendSlice("&amp;"),
            '<' => try out.appendSlice("&lt;"),
            '>' => try out.appendSlice("&gt;"),
            '"' => try out.appendSlice("&quot;"),
            else => try out.append(ch),
        }
    }
    return out.toOwnedSlice();
}

/// Minimal decode for entities when reading attribute *sources* inside (...) so
/// users can write &quot; etc. We only handle a tiny set needed here.
fn decodeMinimalEntities(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    // Fast path: if no '&', return dup
    if (std.mem.indexOfScalar(u8, s, '&') == null) return try allocator.dupe(u8, s);

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < s.len) {
        if (s[i] != '&') {
            try out.append(s[i]);
            i += 1;
            continue;
        }
        // try a few named entities
        if (std.mem.startsWith(u8, s[i..], "&quot;")) {
            try out.append('"');
            i += "&quot;".len;
        } else if (std.mem.startsWith(u8, s[i..], "&amp;")) {
            try out.append('&');
            i += "&amp;".len;
        } else if (std.mem.startsWith(u8, s[i..], "&lt;")) {
            try out.append('<');
            i += "&lt;".len;
        } else if (std.mem.startsWith(u8, s[i..], "&gt;")) {
            try out.append('>');
            i += "&gt;".len;
        } else {
            // unknown; copy verbatim '&' and advance
            try out.append('&');
            i += 1;
        }
    }
    return out.toOwnedSlice();
}

/// Parse the `( ... )` segment of @style(...). Supports:
/// - name:"alias"
/// - classes:"a b"
/// - class:"a b"  (alias for classes, OR if value looks like CSS, treat as style)
/// - style:"color:red"
pub fn parseInlineStyleAttrs(allocator: std.mem.Allocator, raw: []const u8) InlineStyleAttrs {
    // NOTE: best-effort lenient parser; never fails, just returns what it can.
    var attrs: InlineStyleAttrs = .{};

    var i: usize = 0;
    while (i < raw.len) {
        // skip ws and commas
        while (i < raw.len and (isSpace(raw[i]) or raw[i] == ',')) : (i += 1) {}
        if (i >= raw.len) break;

        // parse key
        const key_start = i;
        while (i < raw.len) : (i += 1) {
            const c = raw[i];
            if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '-')) break;
        }
        const key = raw[key_start..i];

        // skip ws
        while (i < raw.len and isSpace(raw[i])) : (i += 1) {}

        if (i >= raw.len or raw[i] != '=') {
            // no value; skip token
            while (i < raw.len and raw[i] != ',') : (i += 1) {}
            continue;
        }
        i += 1; // skip '='

        // skip ws
        while (i < raw.len and isSpace(raw[i])) : (i += 1) {}
        if (i >= raw.len) break;

        // parse value: quoted "...", possibly with &quot; entities
        var val_buf: []u8 = &[_]u8{};
        if (raw[i] == '"') {
            i += 1;
            const start = i;
            while (i < raw.len and raw[i] != '"') : (i += 1) {}
            const end = if (i <= raw.len) i else raw.len;

            const slice = raw[start..end];
            const decoded = decodeMinimalEntities(allocator, slice) catch slice; // best-effort
            // if decode alloc'd, keep; else dup so we can own it? We only need borrowed views.
            // We will store borrowed slices pointing into either decoded (owned) or original raw.
            // To keep memory simple, we leak decoded into this scope and free nothing here
            // (the caller never owns these slices). For safety across calls, store views into decoded.
            val_buf = switch (@typeInfo(@TypeOf(decoded))) {
                .Pointer => decoded,
                else => allocator.dupe(u8, decoded) catch decoded,
            };
            if (i < raw.len and raw[i] == '"') i += 1;
        } else {
            const start = i;
            while (i < raw.len and raw[i] != ',' and !isSpace(raw[i])) : (i += 1) {}
            const slice = raw[start..i];
            val_buf = slice;
        }

        if (asciiEq(key, "name")) {
            attrs.name = val_buf;
        } else if (asciiEq(key, "classes")) {
            attrs.classes = val_buf;
        } else if (asciiEq(key, "class")) {
            attrs.class_attr = val_buf;
        } else if (asciiEq(key, "style")) {
            attrs.style = val_buf;
        } else {
            // ignore unknowns here
        }
    }

    // Interpret class_attr if present
    if (attrs.class_attr) |cval| {
        if (classLooksLikeCss(cval)) {
            if (attrs.style == null) attrs.style = cval;
        } else {
            if (attrs.classes == null) attrs.classes = cval;
        }
    }

    return attrs;
}

/// Core rewriter: scan 's' for inline @style(...)[ws]TEXT@end occurrences.
/// - Emits normal text escaped for HTML
/// - Emits matched directives as <span ...>escaped(TEXT)</span>
/// - Resolves aliases via 'aliases' map when name= is present and classes= absent
pub fn rewriteInlineStyleDirectives(
    allocator: std.mem.Allocator,
    s: []const u8,
    aliases: *const StringMap,
) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    const needle = "@style(";
    var i: usize = 0;

    while (i < s.len) {
        const start_opt = std.mem.indexOfPos(u8, s, i, needle);
        if (start_opt == null) {
            // no more directives; escape the tail and finish
            const tail = try escapeHtml(allocator, s[i..]);
            defer allocator.free(tail);
            try out.appendSlice(tail);
            break;
        }

        const start = start_opt.?;

        // Emit prefix as escaped
        if (start > i) {
            const prefix = try escapeHtml(allocator, s[i..start]);
            defer allocator.free(prefix);
            try out.appendSlice(prefix);
        }

        // Parse "(...)" after "@style("
        const open = start + needle.len;
        if (open >= s.len) {
            // malformed tail; escape the rest and end
            const rest = try escapeHtml(allocator, s[start..]);
            defer allocator.free(rest);
            try out.appendSlice(rest);
            break;
        }

        const paren_end_opt = std.mem.indexOfScalarPos(u8, s, open, ')');
        if (paren_end_opt == null) {
            // malformed; emit literally
            const rest = try escapeHtml(allocator, s[start..]);
            defer allocator.free(rest);
            try out.appendSlice(rest);
            break;
        }
        const paren_end = paren_end_opt.?;

        // Extract raw attrs (borrowed slice)
        const raw_attrs = s[open..paren_end];
        const attrs = parseInlineStyleAttrs(allocator, raw_attrs);

        // After ")", optional whitespace, then inline content until first "@end"
        var p: usize = paren_end + 1;
        while (p < s.len and isSpace(s[p])) : (p += 1) {}

        const end_opt = std.mem.indexOfPos(u8, s, p, "@end");
        if (end_opt == null) {
            // malformed (no closer); emit literally
            const rest = try escapeHtml(allocator, s[start..]);
            defer allocator.free(rest);
            try out.appendSlice(rest);
            break;
        }
        const end_idx = end_opt.?;
        const inner_raw = s[p..end_idx];

        // Determine class/style to render
        var classes_to_use: ?[]const u8 = null;

        if (attrs.classes) |cls| {
            classes_to_use = cls;
        } else if (attrs.name) |nm| {
            if (aliases.get(nm)) |resolved| {
                classes_to_use = resolved;
            }
        }

        // Build the <span ...>escaped(inner)</span>
        const inner_esc = try escapeHtml(allocator, inner_raw);
        defer allocator.free(inner_esc);

        if (attrs.style) |sty| {
            const sty_esc = try escapeHtmlAttr(allocator, sty);
            defer allocator.free(sty_esc);

            try out.appendSlice("<span style=\"");
            try out.appendSlice(sty_esc);
            try out.appendSlice("\">");
            try out.appendSlice(inner_esc);
            try out.appendSlice("</span>");
        } else if (classes_to_use) |cls2| {
            const cls_esc = try escapeHtmlAttr(allocator, cls2);
            defer allocator.free(cls_esc);

            try out.appendSlice("<span class=\"");
            try out.appendSlice(cls_esc);
            try out.appendSlice("\">");
            try out.appendSlice(inner_esc);
            try out.appendSlice("</span>");
        } else {
            // No usable attrs; drop wrapper and just output escaped inner text
            try out.appendSlice(inner_esc);
        }

        // advance past "@end"
        i = end_idx + "@end".len;
    }

    return out.toOwnedSlice();
}

/// Public entry point used by the HTML exporter’s Content branch.
/// It produces *trusted* inline HTML for a paragraph:
/// - Escapes everything
/// - Rewrites inline @style(...)...@end into <span...>…</span>
pub fn renderInline(
    allocator: std.mem.Allocator,
    text: []const u8,
    aliases: *const StringMap,
) ![]u8 {
    // Fast path: no @style(...) found → just escape
    if (std.mem.indexOf(u8, text, "@style(") == null) {
        return escapeHtml(allocator, text);
    }
    return rewriteInlineStyleDirectives(allocator, text, aliases);
}

// ──────────────────────────
// Tests
// ──────────────────────────

test "escapeHtml basics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try escapeHtml(A, "<a & b>");
    defer A.free(out);
    try std.testing.expectEqualStrings("&lt;a &amp; b&gt;", out);
}

test "rewriteInlineStyleDirectives: classes attr" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = StringMap.init(A);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| {
            A.free(e.key_ptr.*);
            // values are borrowed; nothing to free
        }
        aliases.deinit();
    }

    const s =
        \\Before @style(classes:"hl red") hot @end after
    ;
    const out = try rewriteInlineStyleDirectives(A, s, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "Before ") == 0);
    try std.testing.expect(std.mem.indexOf(u8, out, "<span class=\"hl red\">hot</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, " after") != null);
}

test "rewriteInlineStyleDirectives: name alias lookup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = StringMap.init(A);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| {
            A.free(e.key_ptr.*);
        }
        aliases.deinit();
    }
    try aliases.put(try A.dupe(u8, "emph"), "italic text-emphasis");

    const s = "The @style(name:\"emph\") preview @end works.";
    const out = try rewriteInlineStyleDirectives(A, s, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "<span class=\"italic text-emphasis\">preview</span>") != null);
}

test "rewriteInlineStyleDirectives: style attr" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = StringMap.init(A);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| {
            A.free(e.key_ptr.*);
        }
        aliases.deinit();
    }

    const s = "X @style(style:\"color:red; font-weight:bold\") Y @end Z";
    const out = try rewriteInlineStyleDirectives(A, s, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "<span style=\"color:red; font-weight:bold\">Y</span>") != null);
}

test "renderInline escapes when no directive present" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();
    var aliases = StringMap.init(A);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| A.free(e.key_ptr.*);
        aliases.deinit();
    }

    const s = "1 < 2 & 3 > 2";
    const out = try renderInline(A, s, &aliases);
    defer A.free(out);
    try std.testing.expectEqualStrings("1 &lt; 2 &amp; 3 &gt; 2", out);
}

test "malformed @style falls back to literal (escaped)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();
    var aliases = StringMap.init(A);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| A.free(e.key_ptr.*);
        aliases.deinit();
    }

    const s = "Bad @style(class:\"oops\" no close";
    const out = try renderInline(A, s, &aliases);
    defer A.free(out);
    // We didn't crash; we escaped the literal tail
    try std.testing.expect(std.mem.indexOf(u8, out, "@style(") != null);
}
