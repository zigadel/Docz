const std = @import("std");

// ─────────────────────────────────────────────────────────────
// Public attrs struct + free()
// ─────────────────────────────────────────────────────────────

pub const InlineStyleAttrs = struct {
    name: ?[]const u8 = null,
    class_attr: ?[]const u8 = null,
    style: ?[]const u8 = null,
    on_click: ?[]const u8 = null,
    on_hover: ?[]const u8 = null,
    on_focus: ?[]const u8 = null,
};

pub fn freeInlineStyleAttrs(allocator: std.mem.Allocator, a: *InlineStyleAttrs) void {
    if (a.name) |v| allocator.free(v);
    if (a.class_attr) |v| allocator.free(v);
    if (a.style) |v| allocator.free(v);
    if (a.on_click) |v| allocator.free(v);
    if (a.on_hover) |v| allocator.free(v);
    if (a.on_focus) |v| allocator.free(v);
    a.* = InlineStyleAttrs{};
}

// ─────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

fn skipSpacesAndCommas(s: []const u8, start: usize) usize {
    var j = start;
    while (j < s.len and (s[j] == ' ' or s[j] == '\t' or s[j] == '\n' or s[j] == '\r' or s[j] == ',')) : (j += 1) {}
    return j;
}

fn classLooksLikeCss(s: []const u8) bool {
    return std.mem.indexOfScalar(u8, s, ':') != null or std.mem.indexOfScalar(u8, s, ';') != null or std.mem.indexOfScalar(u8, s, '=') != null;
}

fn findClosingParenQuoteAware(s: []const u8, start: usize) ?usize {
    var i = start;
    var in_str = false;
    var q: u8 = 0;
    var esc = false;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (in_str) {
            if (esc) {
                esc = false;
            } else if (c == '\\') {
                esc = true;
            } else if (c == q) {
                in_str = false;
            }
            continue;
        }
        if (c == '"' or c == '\'') {
            in_str = true;
            q = c;
            continue;
        }
        if (c == ')') return i;
    }
    return null;
}

fn scanBracedBodyQuoteAware(s: []const u8, open_idx: usize) ?usize {
    if (open_idx >= s.len or s[open_idx] != '{') return null;
    var i: usize = open_idx + 1;
    var depth: usize = 1;
    var in_str = false;
    var q: u8 = 0;
    var esc = false;

    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (in_str) {
            if (esc) {
                esc = false;
            } else if (c == '\\') {
                esc = true;
            } else if (c == q) {
                in_str = false;
            }
            continue;
        }
        if (c == '"' or c == '\'') {
            in_str = true;
            q = c;
            continue;
        }
        if (c == '{') {
            depth += 1;
        } else if (c == '}') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

fn findAtEndOutsideQuotes(s: []const u8, start: usize) ?usize {
    var i = start;
    var in_str = false;
    var q: u8 = 0;
    var esc = false;

    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (in_str) {
            if (esc) {
                esc = false;
            } else if (c == '\\') {
                esc = true;
            } else if (c == q) {
                in_str = false;
            }
            continue;
        }
        if (c == '"' or c == '\'') {
            in_str = true;
            q = c;
            continue;
        }
        if (c == '@' and i + 4 <= s.len and std.mem.eql(u8, s[i .. i + 4], "@end")) {
            return i;
        }
    }
    return null;
}

// ─────────────────────────────────────────────────────────────
// Escapers
// ─────────────────────────────────────────────────────────────

pub fn escapeHtml(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    for (s) |ch| {
        switch (ch) {
            '<' => try out.appendSlice(allocator, "&lt;"),
            '>' => try out.appendSlice(allocator, "&gt;"),
            '&' => try out.appendSlice(allocator, "&amp;"),
            '"' => try out.appendSlice(allocator, "&quot;"),
            '\'' => try out.appendSlice(allocator, "&#39;"),
            else => try out.append(allocator, ch),
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn escapeHtmlAttr(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    return escapeHtml(allocator, s);
}

fn decodeHtmlQuoteEntities(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    var changed = false;
    var i: usize = 0;
    while (i < s.len) {
        if (std.mem.startsWith(u8, s[i..], "&quot;")) {
            try out.append(allocator, '"');
            i += "&quot;".len;
            changed = true;
            continue;
        }
        if (std.mem.startsWith(u8, s[i..], "&#34;")) {
            try out.append(allocator, '"');
            i += "&#34;".len;
            changed = true;
            continue;
        }
        try out.append(allocator, s[i]);
        i += 1;
    }
    if (!changed) return error.NoChange;
    return out.toOwnedSlice(allocator);
}

// ─────────────────────────────────────────────────────────────
// Attribute parser for @(...)
// ─────────────────────────────────────────────────────────────

fn parseInlineStyleAttrs(allocator: std.mem.Allocator, raw: []const u8) InlineStyleAttrs {
    var owned_buf: ?[]u8 = null;
    const needs_decode = std.mem.indexOf(u8, raw, "&quot;") != null or std.mem.indexOf(u8, raw, "&#34;") != null;

    if (needs_decode) {
        owned_buf = decodeHtmlQuoteEntities(allocator, raw) catch null;
    }
    const s: []const u8 = if (owned_buf) |buf| buf else raw;
    defer if (owned_buf) |buf| allocator.free(buf);

    var out = InlineStyleAttrs{};
    var i: usize = 0;

    while (i < s.len) {
        i = skipSpacesAndCommas(s, i);
        if (i >= s.len) break;

        const key_start = i;
        while (i < s.len and s[i] != '=' and s[i] != ':' and s[i] != ' ' and s[i] != ',' and s[i] != ')') : (i += 1) {}
        const key = std.mem.trim(u8, s[key_start..i], " \t\r\n");

        i = skipSpacesAndCommas(s, i);
        if (i < s.len and (s[i] == '=' or s[i] == ':')) i += 1;
        i = skipSpacesAndCommas(s, i);
        if (i >= s.len) break;

        var value: []const u8 = "";
        if (s[i] == '"') {
            i += 1;
            const vstart = i;
            while (i < s.len and s[i] != '"') : (i += 1) {}
            value = s[vstart..@min(i, s.len)];
            if (i < s.len and s[i] == '"') i += 1;
        } else {
            const vstart = i;
            while (i < s.len and s[i] != ',' and s[i] != ' ' and s[i] != ')') : (i += 1) {}
            value = s[vstart..i];
        }

        if (std.ascii.eqlIgnoreCase(key, "name")) {
            out.name = allocator.dupe(u8, value) catch null;
        } else if (std.ascii.eqlIgnoreCase(key, "class") or std.ascii.eqlIgnoreCase(key, "classes")) {
            out.class_attr = allocator.dupe(u8, value) catch null;
        } else if (std.ascii.eqlIgnoreCase(key, "style")) {
            out.style = allocator.dupe(u8, value) catch null;
        } else if (std.ascii.eqlIgnoreCase(key, "on-click")) {
            out.on_click = allocator.dupe(u8, value) catch null;
        } else if (std.ascii.eqlIgnoreCase(key, "on-hover")) {
            out.on_hover = allocator.dupe(u8, value) catch null;
        } else if (std.ascii.eqlIgnoreCase(key, "on-focus")) {
            out.on_focus = allocator.dupe(u8, value) catch null;
        }

        i = skipSpacesAndCommas(s, i);
        if (i < s.len and s[i] == ',') i += 1;
    }

    return out;
}

// ─────────────────────────────────────────────────────────────
// URL sanity + backticks
// ─────────────────────────────────────────────────────────────

fn urlSafe(s: []const u8) bool {
    var has_alpha = false;
    var has_sep = false;
    for (s) |ch| {
        if ((ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z')) has_alpha = true;
        if (ch == '.' or ch == ':' or ch == '/') has_sep = true;
    }
    return has_alpha and has_sep;
}

fn findBacktickEnd(s: []const u8, start_after_tick: usize) ?usize {
    var j = start_after_tick;
    while (j < s.len) : (j += 1) {
        if (s[j] == '\\' and j + 1 < s.len) {
            j += 1;
            continue;
        }
        if (s[j] == '`') return j;
    }
    return null;
}

fn rewriteBackticks(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\' and i + 1 < s.len) {
            const next = s[i + 1];
            if (next == '`' or next == '$' or next == '\\') {
                try out.append(allocator, next);
                i += 1;
                continue;
            }
        }
        if (s[i] != '`') {
            try out.append(allocator, s[i]);
            continue;
        }

        const end_opt = findBacktickEnd(s, i + 1);
        if (end_opt == null) {
            try out.append(allocator, '`');
            continue;
        }
        const end = end_opt.?;
        const inner = s[i + 1 .. end];
        const escaped = try escapeHtml(allocator, inner);
        defer allocator.free(escaped);

        try out.appendSlice(allocator, "<code>");
        try out.appendSlice(allocator, escaped);
        try out.appendSlice(allocator, "</code>");

        i = end;
    }

    return out.toOwnedSlice(allocator);
}

// ─────────────────────────────────────────────────────────────
// <span ...> builder
// ─────────────────────────────────────────────────────────────

fn renderSpanOpenFromAttrs(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    attrs: InlineStyleAttrs,
    aliases: *const std.StringHashMap([]const u8),
) !void {
    try out.appendSlice(allocator, "<span");

    var class_val: ?[]u8 = null;
    var style_val: ?[]u8 = null;
    defer {
        if (class_val) |v| allocator.free(v);
        if (style_val) |v| allocator.free(v);
    }

    if (attrs.class_attr) |raw_class| {
        if (classLooksLikeCss(raw_class)) {
            style_val = try escapeHtmlAttr(allocator, raw_class);
        } else {
            class_val = try escapeHtmlAttr(allocator, raw_class);
        }
    } else if (attrs.name) |nm| {
        if (aliases.get(nm)) |resolved| {
            class_val = try escapeHtmlAttr(allocator, resolved);
        }
    }

    if (attrs.style) |sty_raw| {
        const esc = try escapeHtmlAttr(allocator, sty_raw);
        if (style_val == null) {
            style_val = esc;
        } else {
            var merged = std.ArrayList(u8){};
            defer merged.deinit(allocator);
            try merged.appendSlice(allocator, style_val.?);
            try merged.appendSlice(allocator, "; ");
            try merged.appendSlice(allocator, esc);
            allocator.free(style_val.?);
            allocator.free(esc);
            style_val = try merged.toOwnedSlice(allocator);
        }
    }

    if (class_val) |cv| {
        try out.appendSlice(allocator, " class=\"");
        try out.appendSlice(allocator, cv);
        try out.appendSlice(allocator, "\"");
    }
    if (style_val) |sv| {
        try out.appendSlice(allocator, " style=\"");
        try out.appendSlice(allocator, sv);
        try out.appendSlice(allocator, "\"");
    }

    if (attrs.on_click) |v| {
        const vv = try escapeHtmlAttr(allocator, v);
        defer allocator.free(vv);
        try out.appendSlice(allocator, " data-on-click=\"");
        try out.appendSlice(allocator, vv);
        try out.appendSlice(allocator, "\"");
    }
    if (attrs.on_hover) |v| {
        const vv = try escapeHtmlAttr(allocator, v);
        defer allocator.free(vv);
        try out.appendSlice(allocator, " data-on-hover=\"");
        try out.appendSlice(allocator, vv);
        try out.appendSlice(allocator, "\"");
    }
    if (attrs.on_focus) |v| {
        const vv = try escapeHtmlAttr(allocator, v);
        defer allocator.free(vv);
        try out.appendSlice(allocator, " data-on-focus=\"");
        try out.appendSlice(allocator, vv);
        try out.appendSlice(allocator, "\"");
    }

    try out.append(allocator, '>');
}

// ─────────────────────────────────────────────────────────────
// Inline style rewriting
// ─────────────────────────────────────────────────────────────

fn rewriteInlineStyles(
    allocator: std.mem.Allocator,
    s: []const u8,
    aliases: *const std.StringHashMap([]const u8),
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    var i: usize = 0;

    while (i < s.len) {
        const idx_paren = std.mem.indexOfPos(u8, s, i, "@(");
        const idx_style = std.mem.indexOfPos(u8, s, i, "@style(");

        if (idx_paren == null and idx_style == null) {
            try out.appendSlice(allocator, s[i..]);
            break;
        }

        var start = s.len;
        var kind: u8 = 0; // 1 = paren, 2 = style
        if (idx_paren) |a| {
            start = a;
            kind = 1;
        }
        if (idx_style) |b| {
            if (b < start) {
                start = b;
                kind = 2;
            }
        }

        try out.appendSlice(allocator, s[i..start]);

        var p: usize = start + (if (kind == 1) 2 else "@style(".len);
        const close_paren = findClosingParenQuoteAware(s, p) orelse {
            try out.appendSlice(allocator, s[start..]);
            return out.toOwnedSlice(allocator);
        };
        var attrs = parseInlineStyleAttrs(allocator, s[p..close_paren]);
        defer freeInlineStyleAttrs(allocator, &attrs);

        p = close_paren + 1;
        while (p < s.len and isSpace(s[p])) : (p += 1) {}

        if (p < s.len and s[p] == '{') {
            const close_brace = scanBracedBodyQuoteAware(s, p) orelse {
                try out.appendSlice(allocator, s[start..]);
                return out.toOwnedSlice(allocator);
            };
            const inner = s[p + 1 .. close_brace];

            try renderSpanOpenFromAttrs(allocator, &out, attrs, aliases);
            try out.appendSlice(allocator, inner);
            try out.appendSlice(allocator, "</span>");

            i = close_brace + 1;
            continue;
        }

        const at_end = findAtEndOutsideQuotes(s, p) orelse {
            try out.appendSlice(allocator, s[start..]);
            return out.toOwnedSlice(allocator);
        };
        const inner2 = s[p..at_end];

        try renderSpanOpenFromAttrs(allocator, &out, attrs, aliases);
        try out.appendSlice(allocator, inner2);
        try out.appendSlice(allocator, "</span>");

        i = at_end + "@end".len;
    }

    return out.toOwnedSlice(allocator);
}

// ─────────────────────────────────────────────────────────────
// Markdown link: [text](url)
// ─────────────────────────────────────────────────────────────

fn rewriteLinks(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < s.len) {
        const lb_opt = std.mem.indexOfScalarPos(u8, s, i, '[');
        if (lb_opt == null) break;
        const lb = lb_opt.?;
        const rb_opt = std.mem.indexOfScalarPos(u8, s, lb + 1, ']');
        if (rb_opt == null) break;
        const rb = rb_opt.?;

        if (rb + 1 >= s.len or s[rb + 1] != '(') {
            i = rb + 1;
            continue;
        }
        const par_close = std.mem.indexOfScalarPos(u8, s, rb + 2, ')') orelse {
            i = rb + 1;
            continue;
        };

        const text_raw = s[lb + 1 .. rb];
        const url_raw = std.mem.trim(u8, s[rb + 2 .. par_close], " \t\r\n");

        if (!urlSafe(url_raw)) {
            try out.appendSlice(allocator, s[i .. par_close + 1]);
            i = par_close + 1;
            continue;
        }

        try out.appendSlice(allocator, s[i..lb]);

        const text = try escapeHtml(allocator, text_raw);
        defer allocator.free(text);
        const url = try escapeHtmlAttr(allocator, url_raw);
        defer allocator.free(url);

        try out.appendSlice(allocator, "<a href=\"");
        try out.appendSlice(allocator, url);
        try out.appendSlice(allocator, "\">");
        try out.appendSlice(allocator, text);
        try out.appendSlice(allocator, "</a>");

        i = par_close + 1;
    }

    try out.appendSlice(allocator, s[i..]);
    return out.toOwnedSlice(allocator);
}

// ─────────────────────────────────────────────────────────────
// Public: master inline pass
// ─────────────────────────────────────────────────────────────

pub fn renderInline(
    allocator: std.mem.Allocator,
    raw: []const u8,
    aliases: *const std.StringHashMap([]const u8),
) ![]u8 {
    const step1 = try rewriteBackticks(allocator, raw);
    defer allocator.free(step1);

    const step2 = try rewriteInlineStyles(allocator, step1, aliases);
    defer allocator.free(step2);

    const step3 = try rewriteLinks(allocator, step2);
    return step3;
}

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

test "inline: backticks and links and style shorthand" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = std.StringHashMap([]const u8).init(A);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| {
            A.free(e.key_ptr.*);
            A.free(e.value_ptr.*);
        }
        aliases.deinit();
    }
    try aliases.put(try A.dupe(u8, "note"), try A.dupe(u8, "rounded bg-yellow-50 px-2"));

    const s =
        \\Use `code` and a [link](https://ziglang.org).
        \\ @(name="note"){nice}
    ;
    const out = try renderInline(A, s, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "<code>code</code>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<a href=\"https://ziglang.org\">link</a>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<span class=\"rounded bg-yellow-50 px-2\">nice</span>") != null);
}

test "inline: explicit @style(... ) content @end is rewritten (class→style heuristic)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = std.StringHashMap([]const u8).init(A);
    defer aliases.deinit();

    const s = "The @style(class=\"color = red\") preview @end server.";
    const out = try renderInline(A, s, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "The <span style=\"color = red\">preview </span> server.") != null);
}

test "inline: explicit with &quot; decodes and rewrites" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = std.StringHashMap([]const u8).init(A);
    defer aliases.deinit();

    const s = "The @style(class=&quot;color = red&quot;) preview @end server.";
    const out = try renderInline(A, s, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "<span style=\"color = red\">preview </span>") != null);
}

test "inline: shorthand paren with quoted brace content" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = std.StringHashMap([]const u8).init(A);
    defer aliases.deinit();

    const s = "@(class=\"x\"){this has \"}\" inside}";
    const out = try renderInline(A, s, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "<span class=\"x\">this has \"}\" inside</span>") != null);
}

test "inline: currency $4.39 is not touched" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var aliases = std.StringHashMap([]const u8).init(A);

    const s = "Price is $4.39 today (no closing dollar).";
    const out = try renderInline(A, s, &aliases);
    defer A.free(out);

    try std.testing.expect(std.mem.eql(u8, out, s));
    aliases.deinit();
}
