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

/// Try a handful of possible symbol names for the Markdown→DCZ importer.
/// If none exist in this build, return a specific error instead of @compileError.
fn importMarkdownToDczCompat(alloc: std.mem.Allocator, input: []const u8) ![]u8 {
    if (comptime @hasDecl(md_import, "importMarkdownToDcz")) {
        return md_import.importMarkdownToDcz(alloc, input);
    } else if (comptime @hasDecl(md_import, "importToDcz")) {
        return md_import.importToDcz(alloc, input);
    } else if (comptime @hasDecl(md_import, "importMdToDcz")) {
        return md_import.importMdToDcz(alloc, input);
    } else if (comptime @hasDecl(md_import, "fromMarkdownToDcz")) {
        return md_import.fromMarkdownToDcz(alloc, input);
    } else if (comptime @hasDecl(md_import, "importMarkdown")) {
        // Some trees expose a generic name
        return md_import.importMarkdown(alloc, input);
    } else {
        return error.MarkdownImportUnavailable;
    }
}

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

    var out = std.ArrayList(u8){};
    defer out.deinit(alloc);

    var buf: [16 * 1024]u8 = undefined;
    var total: usize = 0;
    while (true) {
        const n = try f.read(&buf);
        if (n == 0) break;
        total += n;
        // optional safety cap (~64 MiB)
        if (total > (1 << 26)) return error.FileTooLarge;
        try out.appendSlice(alloc, buf[0..n]);
    }

    return try out.toOwnedSlice(alloc);
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

fn replaceExt(alloc: std.mem.Allocator, path: []const u8, new_ext_with_dot: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(path);
    const stem = std.fs.path.stem(path);
    if (dir) |d| {
        return try std.fmt.allocPrint(alloc, "{s}{c}{s}{s}", .{ d, std.fs.path.sep, stem, new_ext_with_dot });
    } else {
        return try std.fmt.allocPrint(alloc, "{s}{s}", .{ stem, new_ext_with_dot });
    }
}

fn insertCssLinkBeforeHeadClose(alloc: std.mem.Allocator, html: []const u8, href: []const u8) ![]u8 {
    const needle = "</head>";
    const idx_opt = std.mem.indexOf(u8, html, needle);
    if (idx_opt == null) {
        return try std.fmt.allocPrint(alloc, "<link rel=\"stylesheet\" href=\"{s}\">\n{s}", .{ href, html });
    }
    const idx = idx_opt.?;

    var out = std.ArrayList(u8){};
    errdefer out.deinit(alloc);

    try out.appendSlice(alloc, html[0..idx]);
    try out.appendSlice(alloc, "<link rel=\"stylesheet\" href=\"");
    try out.appendSlice(alloc, href);
    try out.appendSlice(alloc, "\">\n");
    try out.appendSlice(alloc, html[idx..]);

    return out.toOwnedSlice(alloc);
}

fn writeIndent(w: anytype, n: usize) !void {
    var k: usize = 0;
    while (k < n) : (k += 1) try w.writeByte(' ');
}

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
    return eqLower(name, "area") or eqLower(name, "base") or eqLower(name, "br") or
        eqLower(name, "col") or eqLower(name, "embed") or eqLower(name, "hr") or
        eqLower(name, "img") or eqLower(name, "input") or eqLower(name, "link") or
        eqLower(name, "meta") or eqLower(name, "param") or eqLower(name, "source") or
        eqLower(name, "track") or eqLower(name, "wbr");
}

fn prettyHtml(alloc: std.mem.Allocator, html: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(alloc);

    var indent: usize = 0;
    var i: usize = 0;

    while (i < html.len) {
        const line_start = i;
        while (i < html.len and html[i] != '\n') : (i += 1) {}
        const raw = html[line_start..i];
        if (i < html.len and html[i] == '\n') i += 1;

        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) {
            try out.append(alloc, '\n');
            continue;
        }

        var j: usize = 0;
        while (j < line.len and isWs(line[j])) : (j += 1) {}

        const starts_with_lt = (j < line.len and line[j] == '<');

        var pre_decr: usize = 0;
        var post_incr: usize = 0;

        if (starts_with_lt) {
            const after_lt = j + 1;
            const is_close = after_lt < line.len and line[after_lt] == '/';
            const is_decl_or_comment = after_lt < line.len and (line[after_lt] == '!' or line[after_lt] == '?');

            var name_start: usize = after_lt;
            if (is_close) name_start += 1;
            while (name_start < line.len and isWs(line[name_start])) : (name_start += 1) {}

            var name_end = name_start;
            while (name_end < line.len) : (name_end += 1) {
                const ch = line[name_end];
                if (ch == '>' or ch == '/' or isWs(ch) or ch == '\n') break;
            }
            const tag_name = if (name_end > name_start) line[name_start..name_end] else line[name_start..name_start];

            const self_closed_syntax = line.len >= 2 and line[line.len - 2] == '/' and line[line.len - 1] == '>';
            const voidish = isVoidTag(tag_name);
            const has_inline_close = std.mem.indexOf(u8, line, "</") != null;

            if (is_close and !is_decl_or_comment) {
                if (indent > 0) pre_decr = 1;
            } else if (!is_decl_or_comment and !self_closed_syntax and !voidish) {
                if (!has_inline_close) post_incr = 1;
            }
        }

        if (pre_decr > 0 and indent >= pre_decr) indent -= pre_decr;

        try out.appendNTimes(alloc, ' ', indent * 2);
        try out.appendSlice(alloc, line);
        try out.append(alloc, '\n');

        indent += post_incr;
    }

    return out.toOwnedSlice(alloc);
}

// ─────────────────────────────────────────────────────────────
// PUBLIC ENTRY
// ─────────────────────────────────────────────────────────────
pub fn run(alloc: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const usage =
        "Usage: docz convert <input.{dcz|md|html|htm|tex}> [--to|-t <output.{dcz|md|html|tex}>]\n" ++
        "       [--css inline|file] [--css-file <path>] [--pretty|--no-pretty]\n";

    const in_path = it.next() orelse {
        std.debug.print("{s}", .{usage});
        return error.Invalid;
    };

    var out_path: ?[]const u8 = null;

    const CssMode = enum { inline_css, file };
    var css_mode: CssMode = .inline_css;
    var css_file: ?[]const u8 = null;

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
            if (std.mem.eql(u8, v, "inline")) css_mode = .inline_css else if (std.mem.eql(u8, v, "file")) css_mode = .file else {
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
        const tokens = try docz.Tokenizer.tokenize(input, alloc);
        defer {
            docz.Tokenizer.freeTokens(alloc, tokens);
            alloc.free(tokens);
        }

        var ast = try docz.Parser.parse(tokens, alloc);
        defer ast.deinit(alloc);

        const out_kind = if (out_path) |p| detectKindFromPath(p) else null;

        if (out_kind == null or out_kind.? == .dcz) {
            out_buf = try alloc.dupe(u8, input);
        } else switch (out_kind.?) {
            .md => out_buf = try md_export.exportAstToMarkdown(&ast, alloc),

            .html => {
                const html_inline = try html_export.exportHtml(&ast, alloc);
                errdefer alloc.free(html_inline);

                if (css_mode == .file) {
                    var css_path: []const u8 = undefined;
                    var css_path_needs_free = false;
                    if (css_file) |p| {
                        css_path = p;
                    } else if (out_path) |to_path| {
                        css_path = try replaceExt(alloc, to_path, ".css");
                        css_path_needs_free = true;
                    } else {
                        css_path = "docz.css";
                    }
                    defer if (css_path_needs_free) alloc.free(css_path);

                    const css_blob = try html_export.collectInlineCss(html_inline, alloc);
                    defer alloc.free(css_blob);
                    try writeFile(css_path, css_blob);

                    const html_no_style = try html_export.stripFirstStyleBlock(html_inline, alloc);
                    alloc.free(html_inline);

                    const html_linked = try insertCssLinkBeforeHeadClose(alloc, html_no_style, css_path);
                    alloc.free(html_no_style);

                    if (pretty) {
                        const pretty_buf = try prettyHtml(alloc, html_linked);
                        alloc.free(html_linked);
                        out_buf = pretty_buf;
                    } else {
                        out_buf = html_linked;
                    }
                } else {
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
        switch (in_kind) {
            .md => {
                out_buf = importMarkdownToDczCompat(alloc, input) catch |e| {
                    if (e == error.MarkdownImportUnavailable) {
                        std.debug.print(
                            "convert: this build lacks a Markdown→DCZ importer in md_import; " ++
                                "rebuild with the markdown importer or use .dcz/.html/.tex.\n",
                            .{},
                        );
                        return error.Invalid;
                    }
                    return e;
                };
            },
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
