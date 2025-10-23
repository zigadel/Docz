const std = @import("std");

// ─────────────────────────────────────────────────────────────
// Tiny HTML escaper
// ─────────────────────────────────────────────────────────────
fn htmlAppendEscChar(out: *std.ArrayList(u8), alloc: std.mem.Allocator, ch: u8) !void {
    switch (ch) {
        '&' => try out.appendSlice(alloc, "&amp;"),
        '<' => try out.appendSlice(alloc, "&lt;"),
        '>' => try out.appendSlice(alloc, "&gt;"),
        '"' => try out.appendSlice(alloc, "&quot;"),
        '\'' => try out.appendSlice(alloc, "&#39;"),
        else => try out.append(alloc, ch),
    }
}

fn htmlEscape(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(alloc);
    for (s) |ch| try htmlAppendEscChar(&out, alloc, ch);
    return out.toOwnedSlice(alloc);
}

fn flushParagraph(p: *std.ArrayList(u8), out: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
    if (p.items.len == 0) return;
    try out.appendSlice(alloc, "<p>");
    try out.appendSlice(alloc, p.items);
    try out.appendSlice(alloc, "</p>\n");
    p.clearRetainingCapacity();
}

// ─────────────────────────────────────────────────────────────
// Inline formatter: **bold**, *italic*, `code`, [text](url)
// ─────────────────────────────────────────────────────────────
fn inlineFormat(alloc: std.mem.Allocator, line: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(alloc);

    var i: usize = 0;
    var em_on = false;
    var strong_on = false;
    var code_on = false;

    while (i < line.len) {
        const c = line[i];

        // Toggle inline code: `code`
        if (c == '`') {
            if (code_on)
                try out.appendSlice(alloc, "</code>")
            else
                try out.appendSlice(alloc, "<code>");
            code_on = !code_on;
            i += 1;
            continue;
        }

        if (!code_on) {
            // Markdown link: [text](url)
            if (c == '[') {
                const close_br = std.mem.indexOfScalarPos(u8, line, i + 1, ']') orelse {
                    try htmlAppendEscChar(&out, alloc, c);
                    i += 1;
                    continue;
                };
                if (close_br + 1 < line.len and line[close_br + 1] == '(') {
                    const close_par = std.mem.indexOfScalarPos(u8, line, close_br + 2, ')') orelse {
                        try htmlAppendEscChar(&out, alloc, c);
                        i += 1;
                        continue;
                    };
                    const text_raw = line[i + 1 .. close_br];
                    const url_raw = line[close_br + 2 .. close_par];

                    const text_esc = try htmlEscape(alloc, text_raw);
                    defer alloc.free(text_esc);
                    const url_esc = try htmlEscape(alloc, url_raw);
                    defer alloc.free(url_esc);

                    try out.appendSlice(alloc, "<a href=\"");
                    try out.appendSlice(alloc, url_esc);
                    try out.appendSlice(alloc, "\">");
                    try out.appendSlice(alloc, text_esc);
                    try out.appendSlice(alloc, "</a>");

                    i = close_par + 1;
                    continue;
                }
            }

            // Strong: **...**
            if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '*') {
                if (strong_on)
                    try out.appendSlice(alloc, "</strong>")
                else
                    try out.appendSlice(alloc, "<strong>");
                strong_on = !strong_on;
                i += 2;
                continue;
            }

            // Emphasis: *...*
            if (line[i] == '*') {
                if (em_on)
                    try out.appendSlice(alloc, "</em>")
                else
                    try out.appendSlice(alloc, "<em>");
                em_on = !em_on;
                i += 1;
                continue;
            }
        }

        // Plain character (escaped)
        try htmlAppendEscChar(&out, alloc, c);
        i += 1;
    }

    // Close any unclosed tags (best-effort)
    if (strong_on) try out.appendSlice(alloc, "</strong>");
    if (em_on) try out.appendSlice(alloc, "</em>");
    if (code_on) try out.appendSlice(alloc, "</code>");

    return out.toOwnedSlice(alloc);
}

// ─────────────────────────────────────────────────────────────
// Minimal fallback renderer (headings/paragraphs/code/math)
// Extracts @meta(title:"...") to fill <title>
// ─────────────────────────────────────────────────────────────
pub fn render(alloc: std.mem.Allocator, dcz: []const u8) ![]u8 {
    var body = std.ArrayList(u8){};
    errdefer body.deinit(alloc);

    var in_style = false;

    var in_code = false;
    var code_lang: []const u8 = "text";

    var in_math = false;
    var math_buf = std.ArrayList(u8){};
    defer math_buf.deinit(alloc);

    var para = std.ArrayList(u8){};
    defer para.deinit(alloc);

    // (optional) title from @meta(title:"...")
    var title_buf = std.ArrayList(u8){};
    defer title_buf.deinit(alloc);
    try title_buf.appendSlice(alloc, "Docz Preview");

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
                try body.appendSlice(alloc, "</code></pre>\n");
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

                try body.appendSlice(alloc, "<p>$$ ");
                try body.appendSlice(alloc, esc);
                try body.appendSlice(alloc, " $$</p>\n");

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
            try body.appendSlice(alloc, esc);
            try body.append(alloc, '\n');
            continue;
        }

        if (in_math) {
            if (line.len != 0) {
                if (math_buf.items.len != 0) try math_buf.append(alloc, ' ');
                try math_buf.appendSlice(alloc, line);
            }
            continue;
        }

        // Block starters
        if (std.mem.startsWith(u8, line, "@style")) {
            try flushParagraph(&para, &body, alloc);
            in_style = true;
            continue;
        }

        if (std.mem.startsWith(u8, line, "@meta")) {
            try flushParagraph(&para, &body, alloc);
            if (std.mem.indexOfScalar(u8, line, '(')) |lp| {
                if (std.mem.indexOfScalarPos(u8, line, lp, ')')) |rp| {
                    const inside = line[lp + 1 .. rp];
                    if (std.mem.indexOf(u8, inside, "title:\"")) |p0| {
                        const start = p0 + 7; // after title:"
                        if (std.mem.indexOfScalarPos(u8, inside, start, '"')) |p1| {
                            title_buf.clearRetainingCapacity();
                            const t_esc = try htmlEscape(alloc, inside[start..p1]);
                            defer alloc.free(t_esc);
                            try title_buf.appendSlice(alloc, t_esc);
                        }
                    }
                }
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "@code")) {
            try flushParagraph(&para, &body, alloc);

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
            try body.appendSlice(alloc, "<pre><code class=\"language-");
            try body.appendSlice(alloc, lang_esc);
            try body.appendSlice(alloc, "\">");
            in_code = true;
            continue;
        }

        if (std.mem.startsWith(u8, line, "@math")) {
            try flushParagraph(&para, &body, alloc);
            in_math = true;
            continue;
        }

        // Blank line ⇒ paragraph break
        if (line.len == 0) {
            try flushParagraph(&para, &body, alloc);
            continue;
        }

        // Headings
        if (std.mem.startsWith(u8, line, "### ")) {
            try flushParagraph(&para, &body, alloc);
            const h = try inlineFormat(alloc, line[4..]);
            defer alloc.free(h);
            try body.appendSlice(alloc, "<h3>");
            try body.appendSlice(alloc, h);
            try body.appendSlice(alloc, "</h3>\n");
            continue;
        }
        if (std.mem.startsWith(u8, line, "## ")) {
            try flushParagraph(&para, &body, alloc);
            const h = try inlineFormat(alloc, line[3..]);
            defer alloc.free(h);
            try body.appendSlice(alloc, "<h2>");
            try body.appendSlice(alloc, h);
            try body.appendSlice(alloc, "</h2>\n");
            continue;
        }
        if (std.mem.startsWith(u8, line, "# ")) {
            try flushParagraph(&para, &body, alloc);
            const h = try inlineFormat(alloc, line[2..]);
            defer alloc.free(h);
            try body.appendSlice(alloc, "<h1>");
            try body.appendSlice(alloc, h);
            try body.appendSlice(alloc, "</h1>\n");
            continue;
        }

        // Normal line → part of current paragraph
        const frag = try inlineFormat(alloc, line);
        defer alloc.free(frag);
        if (para.items.len != 0) try para.append(alloc, ' ');
        try para.appendSlice(alloc, frag);
    }

    // flush trailing paragraph
    try flushParagraph(&para, &body, alloc);

    // wrap document with computed title
    var doc = std.ArrayList(u8){};
    errdefer doc.deinit(alloc);

    try doc.appendSlice(alloc,
        \\<!DOCTYPE html>
        \\<html>
        \\  <head>
        \\    <meta charset="utf-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1" />
        \\    <title>
    );
    try doc.appendSlice(alloc, title_buf.items);
    try doc.appendSlice(alloc,
        \\</title>
        \\  </head>
        \\  <body>
        \\
    );
    try doc.appendSlice(alloc, body.items);
    try doc.appendSlice(alloc,
        \\  </body>
        \\</html>
        \\
    );

    return doc.toOwnedSlice(alloc);
}
