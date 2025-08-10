const std = @import("std");
const docz = @import("docz");

fn contains(hay: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, hay, needle) != null;
}

fn asciiLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn startsWithInsensitive(s: []const u8, tag: []const u8) bool {
    if (s.len < tag.len) return false;
    var j: usize = 0;
    while (j < tag.len) : (j += 1) {
        if (asciiLower(s[j]) != asciiLower(tag[j])) return false;
    }
    return true;
}

fn findInsensitive(hay: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or hay.len < needle.len) return null;
    var k: usize = 0;
    while (k + needle.len <= hay.len) : (k += 1) {
        if (startsWithInsensitive(hay[k..], needle)) return k;
    }
    return null;
}

fn trimSpaces(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn extractBetweenInsensitive(hay: []const u8, start_pat: []const u8, end_pat: []const u8) ?[]const u8 {
    const a = findInsensitive(hay, start_pat) orelse return null;
    const rest = hay[a + start_pat.len ..];
    const b_rel = findInsensitive(rest, end_pat) orelse return null;
    return rest[0..b_rel];
}

fn getAttrLower(tag_inner: []const u8, attr: []const u8) ?[]const u8 {
    // very small attribute scanner: attr="value" or attr='value'
    var j: usize = 0;
    while (j < tag_inner.len) : (j += 1) {
        while (j < tag_inner.len and std.ascii.isWhitespace(tag_inner[j])) : (j += 1) {}
        const key_start = j;
        while (j < tag_inner.len and (std.ascii.isAlphabetic(tag_inner[j]) or tag_inner[j] == '-' or tag_inner[j] == ':')) : (j += 1) {}
        const key = tag_inner[key_start..j];
        if (key.len == 0) break;

        while (j < tag_inner.len and std.ascii.isWhitespace(tag_inner[j])) : (j += 1) {}
        if (j >= tag_inner.len or tag_inner[j] != '=') {
            while (j < tag_inner.len and !std.ascii.isWhitespace(tag_inner[j])) : (j += 1) {}
            continue;
        }
        j += 1; // '='
        while (j < tag_inner.len and std.ascii.isWhitespace(tag_inner[j])) : (j += 1) {}
        if (j >= tag_inner.len) break;

        var quote: u8 = 0;
        if (tag_inner[j] == '"' or tag_inner[j] == '\'') {
            quote = tag_inner[j];
            j += 1;
        }
        const v_start = j;
        if (quote != 0) {
            while (j < tag_inner.len and tag_inner[j] != quote) : (j += 1) {}
            const v = tag_inner[v_start..@min(j, tag_inner.len)];
            if (j < tag_inner.len) j += 1;
            if (std.ascii.eqlIgnoreCase(key, attr)) return v;
        } else {
            while (j < tag_inner.len and !std.ascii.isWhitespace(tag_inner[j]) and tag_inner[j] != '>' and tag_inner[j] != '/') : (j += 1) {}
            const v = tag_inner[v_start..j];
            if (std.ascii.eqlIgnoreCase(key, attr)) return v;
        }
    }
    return null;
}

// ---- emit helpers ----

fn emitMetaKV(w: anytype, k: []const u8, v: []const u8) !void {
    try w.print("@meta({s}=\"{s}\") @end\n", .{ k, v });
}

fn emitTitle(w: anytype, title: []const u8) !void {
    try w.print("@meta(title=\"{s}\") @end\n", .{title});
}

fn emitHeading(w: anytype, level: u8, text: []const u8) !void {
    try w.print("@heading(level={d}) {s} @end\n", .{ level, text });
}

fn emitPara(w: anytype, text: []const u8) !void {
    const t = trimSpaces(text);
    if (t.len == 0) return;
    try w.print("{s}\n", .{t});
}

fn emitImage(w: anytype, src: []const u8) !void {
    try w.print("@image(src=\"{s}\") @end\n", .{src});
}

fn emitImportCss(w: anytype, href: []const u8) !void {
    try w.print("@import(href=\"{s}\") @end\n", .{href});
}

fn emitCode(w: anytype, lang: []const u8, body: []const u8) !void {
    if (lang.len > 0) {
        try w.print("@code(language=\"{s}\")\n{s}\n@end\n", .{ lang, body });
    } else {
        try w.print("@code(language=\"\")\n{s}\n@end\n", .{body});
    }
}

// ---- main API ----

pub fn importHtmlToDcz(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const w = out.writer();

    // HEAD: title/meta/stylesheet
    if (extractBetweenInsensitive(html, "<head", "</head>")) |head| {
        if (extractBetweenInsensitive(head, "<title", "</title>")) |tchunk| {
            const gt = std.mem.indexOfScalar(u8, tchunk, '>') orelse 0;
            const t = trimSpaces(tchunk[gt + 1 ..]);
            if (t.len > 0) try emitTitle(w, t);
        }

        // meta
        var scan: usize = 0;
        while (true) {
            const mpos = findInsensitive(head[scan..], "<meta") orelse break;
            const mstart = scan + mpos;
            const mend_rel = std.mem.indexOfScalar(u8, head[mstart..], '>') orelse break;
            const mend = mstart + mend_rel;
            const inner = head[mstart + "<meta".len .. mend];
            const name = getAttrLower(inner, "name") orelse "";
            const content = getAttrLower(inner, "content") orelse "";
            if (name.len > 0 and content.len > 0) {
                try emitMetaKV(w, name, content);
            }
            scan = mend + 1;
        }

        // link rel=stylesheet
        scan = 0;
        while (true) {
            const lpos = findInsensitive(head[scan..], "<link") orelse break;
            const lstart = scan + lpos;
            const lend_rel = std.mem.indexOfScalar(u8, head[lstart..], '>') orelse break;
            const lend = lstart + lend_rel;
            const inner = head[lstart + "<link".len .. lend];
            const rel = getAttrLower(inner, "rel") orelse "";
            if (rel.len != 0 and std.ascii.eqlIgnoreCase(rel, "stylesheet")) {
                if (getAttrLower(inner, "href")) |href| {
                    if (href.len > 0) try emitImportCss(w, href);
                }
            }
            scan = lend + 1;
        }
    }

    // BODY-ish scan for headings/paras/code/img
    var i: usize = 0;
    while (i < html.len) {
        const lt = std.mem.indexOfScalarPos(u8, html, i, '<') orelse break;

        if (lt > i) {
            const text = trimSpaces(html[i..lt]);
            if (text.len != 0) try emitPara(w, text);
        }

        const rest = html[lt..];

        // headings h1..h6
        var matched_heading = false;
        inline for (.{ 1, 2, 3, 4, 5, 6 }) |lvl| {
            if (!matched_heading) {
                const open_tag = switch (lvl) {
                    1 => "<h1",
                    2 => "<h2",
                    3 => "<h3",
                    4 => "<h4",
                    5 => "<h5",
                    else => "<h6",
                };
                const close_tag = switch (lvl) {
                    1 => "</h1>",
                    2 => "</h2>",
                    3 => "</h3>",
                    4 => "</h4>",
                    5 => "</h5>",
                    else => "</h6>",
                };

                if (startsWithInsensitive(rest, open_tag)) {
                    const gt_rel = std.mem.indexOfScalar(u8, rest, '>') orelse 0;
                    const after = rest[gt_rel + 1 ..];
                    if (findInsensitive(after, close_tag)) |end_rel| {
                        const inner = trimSpaces(after[0..end_rel]);
                        if (inner.len != 0) try emitHeading(w, @intCast(lvl), inner);
                        i = lt + gt_rel + 1 + end_rel + close_tag.len;
                        matched_heading = true;
                    }
                }
            }
        }
        if (matched_heading) continue;

        // <img ...>
        if (startsWithInsensitive(rest, "<img")) {
            const gt_rel = std.mem.indexOfScalar(u8, rest, '>') orelse 0;
            const inner = rest["<img".len..gt_rel];
            if (getAttrLower(inner, "src")) |src| {
                try emitImage(w, src);
            }
            i = lt + gt_rel + 1;
            continue;
        }

        // <pre> ... <code ...>BODY</code> ... </pre>
        if (startsWithInsensitive(rest, "<pre")) {
            const pre_end_rel = findInsensitive(rest, "</pre>") orelse {
                i = lt + 1;
                continue;
            };
            const pre_block = rest[0 .. pre_end_rel + "</pre>".len];
            if (extractBetweenInsensitive(pre_block, "<code", "</code>")) |code_chunk| {
                const gt_rel = std.mem.indexOfScalar(u8, code_chunk, '>') orelse 0;
                const attrs = code_chunk[0..gt_rel];
                const body = code_chunk[gt_rel + 1 ..];
                var lang: []const u8 = "";
                if (getAttrLower(attrs, "class")) |cls| {
                    if (std.mem.startsWith(u8, cls, "language-")) {
                        lang = cls["language-".len..];
                    } else if (std.mem.startsWith(u8, cls, "lang-")) {
                        lang = cls["lang-".len..];
                    }
                }
                try emitCode(w, lang, body);
            }
            i = lt + pre_end_rel + "</pre>".len;
            continue;
        }

        // <p>...</p>
        if (startsWithInsensitive(rest, "<p")) {
            const gt_rel = std.mem.indexOfScalar(u8, rest, '>') orelse 0;
            const after = rest[gt_rel + 1 ..];
            if (findInsensitive(after, "</p>")) |end_rel| {
                try emitPara(w, after[0..end_rel]);
                i = lt + gt_rel + 1 + end_rel + "</p>".len;
                continue;
            }
        }

        // default: skip tag
        const gt_rel = std.mem.indexOfScalar(u8, rest, '>') orelse 0;
        i = lt + gt_rel + 1;
    }

    return out.toOwnedSlice();
}

test "html_import: extracts <title>, <meta>, and <link rel=stylesheet>" {
    const html =
        \\<!doctype html>
        \\<html>
        \\<head>
        \\  <meta name="author" content="Docz Team">
        \\  <meta name="keywords" content="zig,docz">
        \\  <title>My Doc</title>
        \\  <link rel="stylesheet" href="/styles/main.css">
        \\</head>
        \\<body></body>
        \\</html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    try std.testing.expect(contains(out, "@meta(title=\"My Doc\") @end"));
    try std.testing.expect(contains(out, "@meta(author=\"Docz Team\") @end"));
    try std.testing.expect(contains(out, "@meta(keywords=\"zig,docz\") @end"));
    try std.testing.expect(contains(out, "@import(href=\"/styles/main.css\") @end"));
}

test "html_import: headings and paragraphs" {
    const html =
        \\<html>
        \\<body>
        \\  <h1>Top</h1>
        \\  <p>First paragraph.</p>
        \\  <h2>Sub</h2>
        \\  <p>Second paragraph.</p>
        \\</body>
        \\</html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    try std.testing.expect(contains(out, "@heading(level=1) Top @end"));
    try std.testing.expect(contains(out, "First paragraph.\n"));
    try std.testing.expect(contains(out, "@heading(level=2) Sub @end"));
    try std.testing.expect(contains(out, "Second paragraph.\n"));
}

test "html_import: <img src> and <pre><code class=language-*> blocks" {
    const html =
        \\<html>
        \\<body>
        \\  <img src="img/logo.png" alt="x">
        \\  <pre><code class="language-zig">const x = 42;</code></pre>
        \\  <pre><code class="lang-python">print(1)</code></pre>
        \\</body>
        \\</html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    try std.testing.expect(contains(out, "@image(src=\"img/logo.png\") @end"));

    try std.testing.expect(contains(out,
        \\@code(language="zig")
    ));
    try std.testing.expect(contains(out, "const x = 42;"));
    try std.testing.expect(contains(out, "@end\n"));

    try std.testing.expect(contains(out,
        \\@code(language="python")
    ));
    try std.testing.expect(contains(out, "print(1)"));
}

test "html_import: case-insensitive tags and loose whitespace" {
    const html =
        \\<HTML>
        \\<HeAd>
        \\  <TiTlE>  Mixed Case  </TiTlE>
        \\</HeAd>
        \\<BoDy>
        \\  <H3>  Trim Me  </H3>
        \\  <P>   spaced text   </P>
        \\</BoDy>
        \\</HTML>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    try std.testing.expect(contains(out, "@meta(title=\"Mixed Case\") @end"));
    try std.testing.expect(contains(out, "@heading(level=3) Trim Me @end"));
    try std.testing.expect(contains(out, "spaced text\n"));
}

test "html_import: unknown tags are skipped safely" {
    const html =
        \\<html>
        \\<body>
        \\  <div><span>keep this text</span></div>
        \\  <weirdtag foo=bar>ignore me</weirdtag>
        \\  <p>and this too</p>
        \\</body>
        \\</html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importHtmlToDcz(A, html);
    defer A.free(out);

    // We don’t generate a directive for generic DIV/SPAN; we should still grab
    // free text around tags as paragraphs where possible.
    // Minimal parser behavior: at least see the <p> text.
    try std.testing.expect(contains(out, "and this too\n"));
}
