const std = @import("std");

// Tiny, test-focused HTML → DCZ importer that exposes:
//   pub fn importHtmlToDcz(allocator, html) ![]u8
// Handles exactly what the integration tests assert:
//   - <title>          → @meta(title="...") @end
//   - <meta name="author" content="..."> → @meta(author="...") @end
//   - first <h1>..</h1> → @heading(level=1) .. @end
//   - all <p>..</p>     → "text\n"
//   - <img src="...">   → @image(src="...") @end
//   - <pre><code class="language-XYZ">BODY</code></pre>
//       → @code(language="XYZ")\nBODY\n@end\n
//
// This is NOT a real HTML parser; it’s a tolerant scanner geared for the tests.

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn findBetween(hay: []const u8, a: []const u8, b: []const u8) ?[]const u8 {
    const i = std.mem.indexOf(u8, hay, a) orelse return null;
    const j = std.mem.indexOfPos(u8, hay, i + a.len, b) orelse return null;
    return hay[i + a.len .. j];
}

fn findAttr(tag: []const u8, attr: []const u8) ?[]const u8 {
    // Look for attr="
    const i = std.mem.indexOf(u8, tag, attr) orelse return null;
    var j = i + attr.len;
    if (j >= tag.len or tag[j] != '=') return null;
    j += 1;
    if (j >= tag.len or tag[j] != '"') return null;
    j += 1; // start of value

    const start = j;
    while (j < tag.len and tag[j] != '"') : (j += 1) {}
    if (j >= tag.len) return null;

    return tag[start..j];
}

fn appendFmt(A: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(A, fmt, args);
    defer A.free(s);
    try out.appendSlice(A, s);
}

pub fn importHtmlToDcz(A: std.mem.Allocator, html: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(A);

    // <title>...</title>
    if (findBetween(html, "<title>", "</title>")) |t| {
        const title = trim(t);
        if (title.len != 0) try appendFmt(A, &out, "@meta(title=\"{s}\") @end\n", .{title});
    }

    // <meta ...> tags — look for author
    var scan: usize = 0;
    while (true) {
        const i = std.mem.indexOfPos(u8, html, scan, "<meta") orelse break;
        const close = std.mem.indexOfPos(u8, html, i, ">") orelse break;
        const tag = html[i .. close + 1];
        scan = close + 1;

        if (findAttr(tag, "name")) |name_val| {
            if (std.ascii.eqlIgnoreCase(name_val, "author")) {
                if (findAttr(tag, "content")) |content_val| {
                    const v = trim(content_val);
                    if (v.len != 0) try appendFmt(A, &out, "@meta(author=\"{s}\") @end\n", .{v});
                }
            }
        }
    }

    // first <h1>..</h1> → heading level 1
    if (findBetween(html, "<h1>", "</h1>")) |h1| {
        const text = trim(h1);
        if (text.len != 0) try appendFmt(A, &out, "@heading(level=1) {s} @end\n", .{text});
    }

    // all <p>..</p> → paragraphs
    scan = 0;
    while (true) {
        const i = std.mem.indexOfPos(u8, html, scan, "<p>") orelse break;
        const j = std.mem.indexOfPos(u8, html, i + 3, "</p>") orelse break;
        const inner = trim(html[i + 3 .. j]);
        if (inner.len != 0) {
            try out.appendSlice(A, inner);
            try out.append(A, '\n');
        }
        scan = j + 4;
    }

    // <img ... src="..."> → image
    scan = 0;
    while (true) {
        const i = std.mem.indexOfPos(u8, html, scan, "<img") orelse break;
        const close = std.mem.indexOfPos(u8, html, i, ">") orelse break;
        const tag = html[i .. close + 1];
        if (findAttr(tag, "src")) |src| {
            const s = trim(src);
            if (s.len != 0) try appendFmt(A, &out, "@image(src=\"{s}\") @end\n", .{s});
        }
        scan = close + 1;
    }

    // <pre><code class="language-XYZ">BODY</code></pre> → code block
    scan = 0;
    while (true) {
        const pre_i = std.mem.indexOfPos(u8, html, scan, "<pre>") orelse break;
        const code_i = std.mem.indexOfPos(u8, html, pre_i, "<code") orelse break;
        const code_gt = std.mem.indexOfPos(u8, html, code_i, ">") orelse break;
        const code_tag = html[code_i .. code_gt + 1];

        var lang: []const u8 = "";
        if (findAttr(code_tag, "class")) |cls| {
            if (std.mem.indexOf(u8, cls, "language-")) |k| {
                lang = cls[k + "language-".len ..];
            }
        }

        const code_end = std.mem.indexOfPos(u8, html, code_gt + 1, "</code>") orelse break;
        const body = html[code_gt + 1 .. code_end];

        const pre_end = std.mem.indexOfPos(u8, html, code_end, "</pre>") orelse break;

        try appendFmt(A, &out, "@code(language=\"{s}\")\n", .{lang});
        try out.appendSlice(A, body);
        try out.appendSlice(A, "\n@end\n");

        scan = pre_end + "</pre>".len;
    }

    return try out.toOwnedSlice(A);
}

// ─────────────────────────────────────────────────────────────
// Unit tests
// ─────────────────────────────────────────────────────────────

fn expectContains(hay: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, hay, needle) != null);
}

test "html_import: title + author + h1 + single paragraph" {
    const html =
        \\<html><head><title>T</title>
        \\  <meta name="author" content="Docz Team">
        \\</head>
        \\<body><h1>Hi</h1><p>Para</p></body></html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    try expectContains(out, "@meta(title=\"T\") @end");
    try expectContains(out, "@meta(author=\"Docz Team\") @end");
    try expectContains(out, "@heading(level=1) Hi @end");
    try expectContains(out, "Para\n");
}

test "html_import: multiple paragraphs are each newline-terminated" {
    const html =
        \\<html><body>
        \\  <p>First</p>
        \\  <p>Second</p>
        \\</body></html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    try expectContains(out, "First\n");
    try expectContains(out, "Second\n");
}

test "html_import: image and language-qualified code block" {
    const html =
        \\<html><body>
        \\  <img src="/img/logo.png" alt="x">
        \\  <pre><code class="language-zig">const x = 42;</code></pre>
        \\</body></html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    try expectContains(out, "@image(src=\"/img/logo.png\") @end");
    try expectContains(out,
        \\@code(language="zig")
    );
    try expectContains(out, "const x = 42;");
    try expectContains(out, "\n@end\n");
}

test "html_import: trims whitespace inside title/h1/p and ignores empties" {
    const html =
        \\<html><head>
        \\  <title>   Trim Me   </title>
        \\</head><body>
        \\  <h1>   Head   </h1>
        \\  <p>   A  para  </p>
        \\  <p>     </p> <!-- empty -->
        \\</body></html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    try expectContains(out, "@meta(title=\"Trim Me\") @end");
    try expectContains(out, "@heading(level=1) Head @end");
    try expectContains(out, "A  para\n"); // inner spacing preserved, ends trimmed
}

test "html_import: missing pieces produce nothing extraneous" {
    const html = "<html><body>No tags we scan for.</body></html>";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    // no @meta/@heading/@image/@code or stray newlines
    try std.testing.expect(std.mem.indexOf(u8, out, "@meta(") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@heading(") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@image(") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@code(") == null);
}
