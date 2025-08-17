const std = @import("std");

// ─────────────────────────────────────────────────────────────
// Tiny HTML escaper
// ─────────────────────────────────────────────────────────────
fn htmlAppendEscChar(out: *std.ArrayList(u8), ch: u8) !void {
    switch (ch) {
        '&' => try out.appendSlice("&amp;"),
        '<' => try out.appendSlice("&lt;"),
        '>' => try out.appendSlice("&gt;"),
        '"' => try out.appendSlice("&quot;"),
        '\'' => try out.appendSlice("&#39;"),
        else => try out.append(ch),
    }
}

fn htmlEscape(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    for (s) |ch| try htmlAppendEscChar(&out, ch);
    return out.toOwnedSlice();
}

fn flushParagraph(p: *std.ArrayList(u8), out: *std.ArrayList(u8)) !void {
    if (p.items.len == 0) return;
    try out.appendSlice("<p>");
    try out.appendSlice(p.items);
    try out.appendSlice("</p>\n");
    p.clearRetainingCapacity();
}

// ─────────────────────────────────────────────────────────────
// Inline formatter: **bold**, *italic*, `code`, [text](url)
// ─────────────────────────────────────────────────────────────
fn inlineFormat(alloc: std.mem.Allocator, line: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    var i: usize = 0;
    var em_on = false;
    var strong_on = false;
    var code_on = false;

    while (i < line.len) {
        const c = line[i];

        // Toggle inline code: `code`
        if (c == '`') {
            if (code_on) try out.appendSlice("</code>") else try out.appendSlice("<code>");
            code_on = !code_on;
            i += 1;
            continue;
        }

        if (!code_on) {
            // Markdown link: [text](url)
            if (c == '[') {
                const close_br = std.mem.indexOfScalarPos(u8, line, i + 1, ']') orelse {
                    try htmlAppendEscChar(&out, c);
                    i += 1;
                    continue;
                };
                if (close_br + 1 < line.len and line[close_br + 1] == '(') {
                    const close_par = std.mem.indexOfScalarPos(u8, line, close_br + 2, ')') orelse {
                        try htmlAppendEscChar(&out, c);
                        i += 1;
                        continue;
                    };
                    const text_raw = line[i + 1 .. close_br];
                    const url_raw = line[close_br + 2 .. close_par];

                    const text_esc = try htmlEscape(alloc, text_raw);
                    defer alloc.free(text_esc);
                    const url_esc = try htmlEscape(alloc, url_raw);
                    defer alloc.free(url_esc);

                    try out.appendSlice("<a href=\"");
                    try out.appendSlice(url_esc);
                    try out.appendSlice("\">");
                    try out.appendSlice(text_esc);
                    try out.appendSlice("</a>");

                    i = close_par + 1;
                    continue;
                }
            }

            // Strong: **...**
            if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '*') {
                if (strong_on) try out.appendSlice("</strong>") else try out.appendSlice("<strong>");
                strong_on = !strong_on;
                i += 2;
                continue;
            }

            // Emphasis: *...*
            if (line[i] == '*') {
                if (em_on) try out.appendSlice("</em>") else try out.appendSlice("<em>");
                em_on = !em_on;
                i += 1;
                continue;
            }
        }

        // Plain character (escaped)
        try htmlAppendEscChar(&out, c);
        i += 1;
    }

    // Close any unclosed tags (best-effort)
    if (strong_on) try out.appendSlice("</strong>");
    if (em_on) try out.appendSlice("</em>");
    if (code_on) try out.appendSlice("</code>");

    return out.toOwnedSlice();
}

// ─────────────────────────────────────────────────────────────
// Minimal fallback renderer (headings/paragraphs/code/math)
// Extracts @meta(title:"...") to fill <title>
// ─────────────────────────────────────────────────────────────
pub fn render(alloc: std.mem.Allocator, dcz: []const u8) ![]u8 {
    var body = std.ArrayList(u8).init(alloc);
    errdefer body.deinit();

    var in_style = false;

    var in_code = false;
    var code_lang: []const u8 = "text";

    var in_math = false;
    var math_buf = std.ArrayList(u8).init(alloc);
    defer math_buf.deinit();

    var para = std.ArrayList(u8).init(alloc);
    defer para.deinit();

    // (optional) title from @meta(title:"...")
    var title_buf = std.ArrayList(u8).init(alloc);
    defer title_buf.deinit();
    try title_buf.appendSlice("Docz Preview");

    var it = std.mem.splitScalar(u8, dcz, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");

        // Block terminator
        if (std.mem.eql(u8, line, "@end")) {
            if (in_style) {
                in_style = false;
                continue;
            }

            if (in_code) {
                try body.appendSlice("</code></pre>\n");
                in_code = false;
                continue;
            }

            if (in_math) {
                // finalize one KaTeX display block
                const mb = math_buf.items;
                var end = mb.len;
                while (end > 0 and (mb[end - 1] == ' ' or mb[end - 1] == '\t')) end -= 1;

                const esc = try htmlEscape(alloc, mb[0..end]);
                defer alloc.free(esc);

                try body.appendSlice("<p>$$ ");
                try body.appendSlice(esc);
                try body.appendSlice(" $$</p>\n");

                math_buf.clearRetainingCapacity();
                in_math = false;
                continue;
            }
        }

        // Inside blocks
        if (in_style) continue;

        if (in_code) {
            const esc = try htmlEscape(alloc, raw_line);
            defer alloc.free(esc);
            try body.appendSlice(esc);
            try body.append('\n');
            continue;
        }

        if (in_math) {
            if (line.len != 0) {
                if (math_buf.items.len != 0) try math_buf.append(' ');
                try math_buf.appendSlice(line);
            }
            continue;
        }

        // Block starters
        if (std.mem.startsWith(u8, line, "@style")) {
            try flushParagraph(&para, &body);
            in_style = true;
            continue;
        }

        if (std.mem.startsWith(u8, line, "@meta")) {
            try flushParagraph(&para, &body);
            if (std.mem.indexOfScalar(u8, line, '(')) |lp| {
                if (std.mem.indexOfScalarPos(u8, line, lp, ')')) |rp| {
                    const inside = line[lp + 1 .. rp];
                    if (std.mem.indexOf(u8, inside, "title:\"")) |p0| {
                        const start = p0 + 7; // after title:"
                        if (std.mem.indexOfScalarPos(u8, inside, start, '"')) |p1| {
                            title_buf.clearRetainingCapacity();
                            const t_esc = try htmlEscape(alloc, inside[start..p1]);
                            defer alloc.free(t_esc);
                            try title_buf.appendSlice(t_esc);
                        }
                    }
                }
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "@code")) {
            try flushParagraph(&para, &body);

            code_lang = "text";
            if (std.mem.indexOfScalar(u8, line, '(')) |lp| {
                if (std.mem.indexOfScalarPos(u8, line, lp, ')')) |rp| {
                    const inside = line[lp + 1 .. rp];
                    if (std.mem.indexOf(u8, inside, "lang:\"")) |p0| {
                        const start = p0 + 6; // after lang:"
                        if (std.mem.indexOfScalarPos(u8, inside, start, '"')) |p1| {
                            code_lang = inside[start..p1];
                        }
                    }
                }
            }
            const lang_esc = try htmlEscape(alloc, code_lang);
            defer alloc.free(lang_esc);
            try body.appendSlice("<pre><code class=\"language-");
            try body.appendSlice(lang_esc);
            try body.appendSlice("\">");
            in_code = true;
            continue;
        }

        if (std.mem.startsWith(u8, line, "@math")) {
            try flushParagraph(&para, &body);
            in_math = true;
            continue;
        }

        // Blank line ⇒ paragraph break
        if (line.len == 0) {
            try flushParagraph(&para, &body);
            continue;
        }

        // Headings
        if (std.mem.startsWith(u8, line, "### ")) {
            try flushParagraph(&para, &body);
            const h = try inlineFormat(alloc, line[4..]);
            defer alloc.free(h);
            try body.appendSlice("<h3>");
            try body.appendSlice(h);
            try body.appendSlice("</h3>\n");
            continue;
        }
        if (std.mem.startsWith(u8, line, "## ")) {
            try flushParagraph(&para, &body);
            const h = try inlineFormat(alloc, line[3..]);
            defer alloc.free(h);
            try body.appendSlice("<h2>");
            try body.appendSlice(h);
            try body.appendSlice("</h2>\n");
            continue;
        }
        if (std.mem.startsWith(u8, line, "# ")) {
            try flushParagraph(&para, &body);
            const h = try inlineFormat(alloc, line[2..]);
            defer alloc.free(h);
            try body.appendSlice("<h1>");
            try body.appendSlice(h);
            try body.appendSlice("</h1>\n");
            continue;
        }

        // Normal line → part of current paragraph
        const frag = try inlineFormat(alloc, line);
        defer alloc.free(frag);
        if (para.items.len != 0) try para.append(' ');
        try para.appendSlice(frag);
    }

    // flush trailing paragraph
    try flushParagraph(&para, &body);

    // wrap document with computed title
    var doc = std.ArrayList(u8).init(alloc);
    errdefer doc.deinit();

    try doc.appendSlice(
        \\<!DOCTYPE html>
        \\<html>
        \\  <head>
        \\    <meta charset="utf-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1" />
        \\    <title>
    );
    try doc.appendSlice(title_buf.items);
    try doc.appendSlice(
        \\</title>
        \\  </head>
        \\  <body>
        \\
    );
    try doc.appendSlice(body.items);
    try doc.appendSlice(
        \\  </body>
        \\</html>
        \\
    );

    return doc.toOwnedSlice();
}
