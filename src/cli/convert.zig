const std = @import("std");
const docz = @import("docz");

// internal converters (wired via build.zig)
const html_import = @import("html_import");
const html_export = @import("html_export");
const md_import = @import("md_import");
const md_export = @import("md_export");
const latex_import = @import("latex_import");
const latex_export = @import("latex_export");

pub const Kind = enum { dcz, md, html, tex };

fn detectKindFromPath(p: []const u8) ?Kind {
    const ext = std.fs.path.extension(p);
    if (ext.len == 0) return null;
    if (std.ascii.eqlIgnoreCase(ext, ".dcz")) return .dcz;
    if (std.ascii.eqlIgnoreCase(ext, ".md")) return .md;
    if (std.ascii.eqlIgnoreCase(ext, ".html") or std.ascii.eqlIgnoreCase(ext, ".htm")) return .html;
    if (std.ascii.eqlIgnoreCase(ext, ".tex")) return .tex;
    return null;
}

fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    return try f.readToEndAlloc(alloc, 1 << 26);
}

fn writeFile(path: []const u8, data: []const u8) !void {
    const cwd = std.fs.cwd();
    if (std.fs.path.dirname(path)) |dirpart| {
        try cwd.makePath(dirpart);
    }
    var f = try cwd.createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}

// Robust: same directory as input; just replace extension.
fn replaceExt(alloc: std.mem.Allocator, path: []const u8, new_ext_with_dot: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(path);
    const stem = std.fs.path.stem(path); // base name without extension

    if (dir) |d| {
        // docs/spec-file.html -> docs/spec-file.css
        return try std.fmt.allocPrint(alloc, "{s}{c}{s}{s}", .{ d, std.fs.path.sep, stem, new_ext_with_dot });
    } else {
        // spec-file.html -> spec-file.css
        return try std.fmt.allocPrint(alloc, "{s}{s}", .{ stem, new_ext_with_dot });
    }
}

fn insertCssLinkBeforeHeadClose(alloc: std.mem.Allocator, html: []const u8, href: []const u8) ![]u8 {
    const needle = "</head>";
    const idx_opt = std.mem.indexOf(u8, html, needle);
    if (idx_opt == null) {
        // no </head>? prepend for robustness
        return try std.fmt.allocPrint(alloc, "<link rel=\"stylesheet\" href=\"{s}\">\n{s}", .{ href, html });
    }
    const idx = idx_opt.?;
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    try out.appendSlice(html[0..idx]);
    try out.appendSlice("<link rel=\"stylesheet\" href=\"");
    try out.appendSlice(href);
    try out.appendSlice("\">\n");
    try out.appendSlice(html[idx..]);

    return out.toOwnedSlice();
}

fn writeIndent(w: anytype, n: usize) !void {
    var k: usize = 0;
    while (k < n) : (k += 1) try w.writeByte(' ');
}

// ── Pretty-printer helpers (only what we use) ────────────────
fn isWs(b: u8) bool {
    return b == ' ' or b == '\t' or b == '\r';
}
fn lowerAscii(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn eqLower(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (lowerAscii(a[i]) != lowerAscii(b[i])) return false;
    }
    return true;
}
fn isVoidTag(name: []const u8) bool {
    // HTML5 void elements
    return eqLower(name, "area") or eqLower(name, "base") or eqLower(name, "br") or
        eqLower(name, "col") or eqLower(name, "embed") or eqLower(name, "hr") or
        eqLower(name, "img") or eqLower(name, "input") or eqLower(name, "link") or
        eqLower(name, "meta") or eqLower(name, "param") or eqLower(name, "source") or
        eqLower(name, "track") or eqLower(name, "wbr");
}

// ── Pretty printer (single implementation) ───────────────────
fn prettyHtml(alloc: std.mem.Allocator, html: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    var indent: usize = 0;
    var i: usize = 0;

    while (i < html.len) {
        const line_start = i;
        while (i < html.len and html[i] != '\n') : (i += 1) {}
        const raw = html[line_start..i];
        if (i < html.len and html[i] == '\n') i += 1; // consume newline

        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) {
            try out.append('\n');
            continue;
        }

        // Analyze the line
        var j: usize = 0;
        while (j < line.len and isWs(line[j])) : (j += 1) {}

        const starts_with_lt = (j < line.len and line[j] == '<');

        var pre_decr: usize = 0;
        var post_incr: usize = 0;

        if (starts_with_lt) {
            const after_lt = j + 1;
            const is_close = after_lt < line.len and line[after_lt] == '/';
            const is_decl_or_comment = after_lt < line.len and (line[after_lt] == '!' or line[after_lt] == '?');

            // Parse tag name
            var name_start: usize = after_lt;
            if (is_close) name_start += 1; // runtime increment only

            while (name_start < line.len and isWs(line[name_start])) : (name_start += 1) {}

            var name_end = name_start;
            while (name_end < line.len) : (name_end += 1) {
                const ch = line[name_end];
                if (ch == '>' or ch == '/' or isWs(ch) or ch == '\n') break;
            }
            const tag_name = if (name_end > name_start) line[name_start..name_end] else line[name_start..name_start];

            // Self-close syntax and void detection
            const self_closed_syntax = line.len >= 2 and line[line.len - 2] == '/' and line[line.len - 1] == '>';
            const voidish = isVoidTag(tag_name);

            // Does this same line contain a closing tag too? (e.g., <h1>hi</h1>)
            const has_inline_close = std.mem.indexOf(u8, line, "</") != null;

            if (is_close and !is_decl_or_comment) {
                if (indent > 0) pre_decr = 1;
            } else if (!is_decl_or_comment and !self_closed_syntax and !voidish) {
                if (!has_inline_close) {
                    post_incr = 1;
                }
            }
        }

        if (pre_decr > 0 and indent >= pre_decr) indent -= pre_decr;

        // Emit line with current indent
        try out.appendNTimes(' ', indent * 2);
        try out.appendSlice(line);
        try out.append('\n');

        indent += post_incr;
    }

    return out.toOwnedSlice();
}

// ─────────────────────────────────────────────────────────────
// PUBLIC ENTRY (called by main.zig)
// ─────────────────────────────────────────────────────────────
pub fn run(alloc: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const usage =
        "Usage: docz convert <input.{dcz|md|html|htm|tex}> [--to|-t <output.{dcz|md|html|tex}>]\n" ++
        "       [--css inline|file] [--css-file <path>] [--pretty|--no-pretty]\n";

    const in_path = it.next() orelse {
        std.debug.print("{s}", .{usage});
        return error.Invalid;
    };

    // flags
    var out_path: ?[]const u8 = null;

    // NOTE: identifier can't be named "inline" in Zig; use inline_css
    const CssMode = enum { inline_css, file };
    var css_mode: CssMode = .inline_css;
    var css_file: ?[]const u8 = null;

    // pretty printing: default ON
    var pretty: bool = true;

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--to") or std.mem.eql(u8, arg, "-t")) {
            out_path = it.next() orelse {
                std.debug.print("convert: --to requires a value\n", .{});
                return error.Invalid;
            };
        } else if (std.mem.eql(u8, arg, "--css")) {
            const v = it.next() orelse {
                std.debug.print("convert: --css requires a value: inline|file\n", .{});
                return error.Invalid;
            };
            if (std.mem.eql(u8, v, "inline")) {
                css_mode = .inline_css;
            } else if (std.mem.eql(u8, v, "file")) {
                css_mode = .file;
            } else {
                std.debug.print("convert: --css must be 'inline' or 'file' (got '{s}')\n", .{v});
                return error.Invalid;
            }
        } else if (std.mem.eql(u8, arg, "--css-file")) {
            css_file = it.next() orelse {
                std.debug.print("convert: --css-file requires a value\n", .{});
                return error.Invalid;
            };
        } else if (std.mem.eql(u8, arg, "--pretty")) {
            pretty = true;
        } else if (std.mem.eql(u8, arg, "--no-pretty")) {
            pretty = false;
        } else {
            std.debug.print("convert: unknown arg: {s}\n", .{arg});
            return error.Invalid;
        }
    }

    const in_kind = detectKindFromPath(in_path) orelse {
        std.debug.print("convert: unsupported input type: {s}\n", .{in_path});
        return error.Invalid;
    };

    const input = readFileAlloc(alloc, in_path) catch |e| {
        const cwd_buf: ?[]u8 = std.fs.cwd().realpathAlloc(alloc, ".") catch null;
        defer if (cwd_buf) |buf| alloc.free(buf);
        const cwd = cwd_buf orelse "<?>";

        std.debug.print("convert: failed to read '{s}' (cwd: {s}): {s}\n", .{ in_path, cwd, @errorName(e) });
        return e;
    };
    defer alloc.free(input);

    var out_buf: []u8 = &[_]u8{};
    defer if (out_buf.len != 0 and out_buf.ptr != input.ptr) alloc.free(out_buf);

    if (in_kind == .dcz) {
        // DCZ -> AST
        const tokens = try docz.Tokenizer.tokenize(input, alloc);
        defer {
            docz.Tokenizer.freeTokens(alloc, tokens);
            alloc.free(tokens);
        }

        var ast = try docz.Parser.parse(tokens, alloc);
        defer ast.deinit();

        const out_kind = if (out_path) |p| detectKindFromPath(p) else null;

        if (out_kind == null or out_kind.? == .dcz) {
            out_buf = try alloc.dupe(u8, input);
        } else switch (out_kind.?) {
            .md => out_buf = try md_export.exportAstToMarkdown(&ast, alloc),

            .html => {
                // 1) start with inline <style> included by the exporter
                const html_inline = try html_export.exportHtml(&ast, alloc);
                errdefer alloc.free(html_inline);

                if (css_mode == .file) {
                    // 2) decide CSS path (+ ownership)
                    var css_path: []const u8 = undefined;
                    var css_path_needs_free = false;
                    if (css_file) |p| {
                        css_path = p; // user-provided; not owned
                    } else if (out_path) |to_path| {
                        css_path = try replaceExt(alloc, to_path, ".css");
                        css_path_needs_free = true; // owned
                    } else {
                        css_path = "docz.css"; // fallback; not owned
                    }
                    defer if (css_path_needs_free) alloc.free(css_path);

                    // 3) validate extension if present
                    const ext = std.fs.path.extension(css_path);
                    if (ext.len != 0 and !std.ascii.eqlIgnoreCase(ext, ".css")) {
                        std.debug.print("convert: --css-file should end with .css (got {s})\n", .{css_path});
                        return error.Invalid;
                    }

                    // 4) collect CSS from AST and write it
                    const css_blob = try html_export.collectInlineCss(&ast, alloc);
                    defer alloc.free(css_blob);
                    try writeFile(css_path, css_blob);

                    // 5) strip first <style>…</style> from HTML
                    const html_no_style = try html_export.stripFirstStyleBlock(html_inline, alloc);
                    alloc.free(html_inline);

                    // 6) inject <link> before </head>
                    const html_linked = try insertCssLinkBeforeHeadClose(alloc, html_no_style, css_path);
                    alloc.free(html_no_style);

                    // 7) pretty if requested
                    if (pretty) {
                        const pretty_buf = try prettyHtml(alloc, html_linked);
                        alloc.free(html_linked);
                        out_buf = pretty_buf;
                    } else {
                        out_buf = html_linked;
                    }
                } else {
                    // inline mode (default)
                    if (pretty) {
                        const pretty_buf = try prettyHtml(alloc, html_inline);
                        alloc.free(html_inline);
                        out_buf = pretty_buf;
                    } else {
                        out_buf = html_inline;
                    }
                }
            },

            .tex => out_buf = try latex_export.exportAstToLatex(&ast, alloc),
            .dcz => unreachable,
        }
    } else {
        // Import -> DCZ
        switch (in_kind) {
            .md => out_buf = try md_import.importMarkdownToDcz(alloc, input),
            .html => out_buf = try html_import.importHtmlToDcz(alloc, input),
            .tex => out_buf = try latex_import.importLatexToDcz(alloc, input),
            .dcz => unreachable,
        }
    }

    if (out_path) |p| {
        if (detectKindFromPath(p) == null) {
            std.debug.print("convert: unsupported output type: {s}\n", .{p});
            return error.Invalid;
        }
        try writeFile(p, out_buf);
    } else {
        // Print buffer
        std.debug.print("{s}", .{out_buf});
    }
}

test "convert.detectKindFromPath: basic mapping" {
    try std.testing.expect(detectKindFromPath("a.dcz") == .dcz);
    try std.testing.expect(detectKindFromPath("a.MD") == .md);
    try std.testing.expect(detectKindFromPath("a.html") == .html);
    try std.testing.expect(detectKindFromPath("a.HTM") == .html);
    try std.testing.expect(detectKindFromPath("a.tex") == .tex);
    try std.testing.expect(detectKindFromPath("noext") == null);
}
