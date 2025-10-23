const std = @import("std");

// -----------------------------------------------------------------------------
// Small writer adapter for ArrayList(u8) on this Zig version
//   - No std.io.Writer dependency
//   - Supports writeAll + print via std.fmt.format(self, ...)
// -----------------------------------------------------------------------------
const ListWriter = struct {
    list: *std.ArrayList(u8),
    alloc: std.mem.Allocator,

    pub fn write(self: *ListWriter, bytes: []const u8) !usize {
        try self.list.appendSlice(self.alloc, bytes);
        return bytes.len;
    }

    pub fn writeAll(self: *ListWriter, bytes: []const u8) !void {
        _ = try self.write(bytes);
    }

    // zig 0.16 friendly: allocate formatted text, append, free
    pub fn print(self: *ListWriter, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.alloc, fmt, args);
        defer self.alloc.free(s);
        try self.list.appendSlice(self.alloc, s);
    }
};

// -------------------------
// Small helpers
// -------------------------

fn flushParagraph(A: std.mem.Allocator, out: *std.ArrayList(u8), para: *std.ArrayList(u8)) !void {
    if (para.items.len == 0) return;

    // Trim leading/trailing whitespace in the paragraph buffer
    const trimmed = std.mem.trim(u8, para.items, " \t\r\n");
    if (trimmed.len != 0) {
        try out.appendSlice(A, trimmed);
        try out.append(A, '\n');
    }

    para.clearRetainingCapacity();
}

fn trimSpaces(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphabetic(c);
}

/// Reads a LaTeX command name starting at `start` where `tex[start] == '\'`.
/// Returns name slice and index just after the name.
fn readCommandName(tex: []const u8, start: usize) ?struct { name: []const u8, next: usize } {
    if (start >= tex.len or tex[start] != '\\') return null;
    var j = start + 1;
    while (j < tex.len and isIdentChar(tex[j])) : (j += 1) {}
    if (j == start + 1) return null;
    return .{ .name = tex[start + 1 .. j], .next = j };
}

/// If the next non-space is `[`, read until matching `]` (no nesting).
/// Returns slice inside `[]` and index after `]`. If not present, returns null.
fn readOptionalBracket(tex: []const u8, start: usize) ?struct { body: []const u8, next: usize } {
    var i = start;
    while (i < tex.len and std.ascii.isWhitespace(tex[i])) : (i += 1) {}
    if (i >= tex.len or tex[i] != '[') return null;

    var j = i + 1;
    while (j < tex.len and tex[j] != ']') : (j += 1) {}
    const end = if (j < tex.len) j else tex.len;
    const body = tex[i + 1 .. end];
    const next = if (j < tex.len) j + 1 else j;
    return .{ .body = body, .next = next };
}

/// Read a `{...}` group with brace-depth counting. Start must point at `{`.
/// Returns slice inside braces and index after closing `}`.
fn readBalancedBraces(tex: []const u8, start: usize) ?struct { body: []const u8, next: usize } {
    if (start >= tex.len or tex[start] != '{') return null;
    var depth: usize = 1;
    var j = start + 1;
    while (j < tex.len) : (j += 1) {
        const c = tex[j];
        if (c == '{') {
            depth += 1;
        } else if (c == '}') {
            depth -= 1;
            if (depth == 0) {
                const body = tex[start + 1 .. j];
                return .{ .body = body, .next = j + 1 };
            }
        }
    }
    return null; // unclosed
}

/// Read a \begin{name} ... \end{name} environment starting at `start` where tex[start] == '\\'.
/// Returns env name, body, and index just after the matching end.
fn readEnvironment(tex: []const u8, start: usize) ?struct {
    env: []const u8,
    body: []const u8,
    next: usize,
} {
    const begin_cmd = readCommandName(tex, start) orelse return null;
    if (!std.ascii.eqlIgnoreCase(begin_cmd.name, "begin")) return null;

    const begin_brace = readBalancedBraces(tex, begin_cmd.next) orelse return null;
    const env_name = begin_brace.body;

    var scan = begin_brace.next;
    while (scan < tex.len) {
        const maybe_cmd = readCommandName(tex, scan) orelse {
            scan += 1;
            continue;
        };
        if (std.ascii.eqlIgnoreCase(maybe_cmd.name, "end")) {
            if (readBalancedBraces(tex, maybe_cmd.next)) |end_brace| {
                if (std.ascii.eqlIgnoreCase(end_brace.body, env_name)) {
                    const body_slice = tex[begin_brace.next..scan];
                    return .{ .env = env_name, .body = body_slice, .next = end_brace.next };
                }
            }
        }
        scan = maybe_cmd.next;
    }
    return null;
}

/// Collapse all whitespace runs to a single space and trim ends.
fn collapseSpaces(A: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(A);

    var i: usize = 0;
    var in_space = false;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            if (!in_space) {
                in_space = true;
                try out.append(A, ' ');
            }
        } else {
            in_space = false;
            try out.append(A, c);
        }
    }
    // trim leading/trailing single space
    while (out.items.len != 0 and out.items[0] == ' ')
        _ = out.orderedRemove(0);
    while (out.items.len != 0 and out.items[out.items.len - 1] == ' ')
        _ = out.pop();

    return try out.toOwnedSlice(A);
}

/// Remove all backslashes, then trim spaces.
fn stripBackslashesAndTrim(A: std.mem.Allocator, s: []const u8) ![]u8 {
    var tmp = std.ArrayList(u8){};
    errdefer tmp.deinit(A);
    for (s) |ch| {
        if (ch != '\\') try tmp.append(A, ch);
    }
    const v = trimSpaces(tmp.items);
    return A.dupe(u8, v);
}

// -------------------------
// Emit helpers (dcz)
// -------------------------

fn emitMetaKV(w: anytype, k: []const u8, v: []const u8) !void {
    const key = trimSpaces(k);
    const val = trimSpaces(v);
    if (key.len == 0 or val.len == 0) return;
    try w.print("@meta({s}=\"{s}\") @end\n", .{ key, val });
}

fn emitTitle(w: anytype, title: []const u8) !void {
    const t = trimSpaces(title);
    if (t.len == 0) return;
    try w.print("@meta(title=\"{s}\") @end\n", .{t});
}

fn emitHeading(w: anytype, level: u8, text: []const u8) !void {
    const t = trimSpaces(text);
    if (t.len == 0) return;
    try w.print("@heading(level={d}) {s} @end\n", .{ level, t });
}

fn emitPara(w: anytype, text: []const u8) !void {
    const t = trimSpaces(text);
    if (t.len == 0) return;
    try w.print("{s}\n", .{t});
}

fn emitImage(w: anytype, src: []const u8) !void {
    const s = trimSpaces(src);
    if (s.len == 0) return;
    try w.print("@image(src=\"{s}\") @end\n", .{s});
}

fn emitCode(w: anytype, body: []const u8) !void {
    try w.print("@code(language=\"\")\n{s}\n@end\n", .{body});
}

fn emitMath(w: anytype, body: []const u8) !void {
    const t = trimSpaces(body);
    if (t.len == 0) return;
    try w.print("@math {s} @end\n", .{t});
}

fn flushPara(wr: anytype, buf: *std.ArrayList(u8)) !void {
    const t = trimSpaces(buf.items);
    if (t.len != 0) try emitPara(wr, t);
    buf.clearRetainingCapacity();
}

// -------------------------
// Core conversion
// -------------------------

/// Convert a small, practical subset of LaTeX to .dcz text.
/// Non-matching commands are skipped; plain text becomes paragraphs.
pub fn importLatexToDcz(A: std.mem.Allocator, tex: []const u8) ![]u8 {
    var out_buf = std.ArrayList(u8){};
    errdefer out_buf.deinit(A);

    var para_buf = std.ArrayList(u8){};
    defer para_buf.deinit(A);

    // writer over out_buf
    var lw = ListWriter{ .list = &out_buf, .alloc = A };
    const wr = &lw;

    var i: usize = 0;
    while (i < tex.len) {
        const c = tex[i];

        // Blank line = paragraph boundary
        if (c == '\n') {
            const next_nl: u8 = if (i + 1 < tex.len) tex[i + 1] else 0;
            if (next_nl == '\n') {
                try flushParagraph(A, &out_buf, &para_buf);
                i += 2;
                continue;
            }
        }

        if (c == '\\') {
            // Handle "\\" disambiguation
            if (i + 1 < tex.len and tex[i + 1] == '\\') {
                if (i + 2 < tex.len and std.ascii.isAlphabetic(tex[i + 2])) {
                    i += 1; // let the next '\' start a command
                } else {
                    // Real LaTeX line break -> single space
                    const need_space =
                        para_buf.items.len == 0 or
                        (para_buf.items[para_buf.items.len - 1] != ' ' and
                            para_buf.items[para_buf.items.len - 1] != '\n');
                    if (need_space) try para_buf.append(A, ' ');
                    i += 2;
                    continue;
                }
            }

            // 1) Environments: \begin{...} ... \end{...}
            if (readEnvironment(tex, i)) |env| {
                try flushParagraph(A, &out_buf, &para_buf);

                if (std.ascii.eqlIgnoreCase(env.env, "verbatim")) {
                    try emitCode(wr, env.body);
                } else if (std.ascii.eqlIgnoreCase(env.env, "equation") or
                    std.ascii.eqlIgnoreCase(env.env, "equation*"))
                {
                    // Normalize whitespace inside math.
                    const collapsed = try collapseSpaces(A, env.body);
                    defer A.free(collapsed);

                    // Trim any trailing '\' (and spaces before it) from the math body.
                    var view = collapsed;
                    while (view.len > 0 and (view[view.len - 1] == ' ' or view[view.len - 1] == '\\')) {
                        view = view[0 .. view.len - 1];
                    }

                    if (view.len != 0) {
                        try emitMath(wr, view);
                    }
                } else {
                    // Unknown env: ignore for now.
                }

                i = env.next;
                continue;
            }

            // 2) Simple commands
            if (readCommandName(tex, i)) |cmd| {
                const name = cmd.name;

                // \title{...} / \author{...}
                if (std.ascii.eqlIgnoreCase(name, "title") or
                    std.ascii.eqlIgnoreCase(name, "author"))
                {
                    if (readBalancedBraces(tex, cmd.next)) |grp| {
                        try flushParagraph(A, &out_buf, &para_buf);
                        if (std.ascii.eqlIgnoreCase(name, "title")) {
                            try emitTitle(wr, grp.body);
                        } else {
                            try emitMetaKV(wr, "author", grp.body);
                        }
                        i = grp.next;
                        continue;
                    }
                }

                // \section / \subsection / \subsubsection
                if (std.ascii.eqlIgnoreCase(name, "section") or
                    std.ascii.eqlIgnoreCase(name, "subsection") or
                    std.ascii.eqlIgnoreCase(name, "subsubsection"))
                {
                    if (readBalancedBraces(tex, cmd.next)) |grp| {
                        try flushParagraph(A, &out_buf, &para_buf);
                        const lvl: u8 =
                            if (std.ascii.eqlIgnoreCase(name, "section")) 1 else if (std.ascii.eqlIgnoreCase(name, "subsection")) 2 else 3;
                        try emitHeading(wr, lvl, grp.body);
                        i = grp.next;
                        continue;
                    }
                }

                // \includegraphics[...]{path}
                if (std.ascii.eqlIgnoreCase(name, "includegraphics")) {
                    const opt = readOptionalBracket(tex, cmd.next); // ignored for now
                    const after = if (opt) |o| o.next else cmd.next;
                    if (readBalancedBraces(tex, after)) |grp| {
                        try flushParagraph(A, &out_buf, &para_buf);
                        try emitImage(wr, grp.body);
                        i = grp.next;
                        continue;
                    }
                }

                // Unknown command: drop command + one braced arg if present
                if (readBalancedBraces(tex, cmd.next)) |grp| {
                    i = grp.next;
                } else {
                    i = cmd.next;
                }
                continue;
            }
        }

        // Default: accumulate paragraph text
        try para_buf.append(A, c);
        i += 1;
    }

    // Final flush
    try flushParagraph(A, &out_buf, &para_buf);
    return try out_buf.toOwnedSlice(A);
}

// -------------------------
// Low-level bracket readers
// -------------------------

fn readBraced(A: std.mem.Allocator, tex: []const u8, idx: *usize) ![]u8 {
    var i = idx.*;
    if (i >= tex.len or tex[i] != '{') return A.alloc(u8, 0);
    i += 1;
    const start = i;
    var depth: usize = 1;
    while (i < tex.len and depth > 0) {
        if (tex[i] == '{') depth += 1 else if (tex[i] == '}') depth -= 1;
        i += 1;
    }
    idx.* = i;
    return A.dupe(u8, tex[start .. i - 1]);
}

fn readBracketed(A: std.mem.Allocator, tex: []const u8, idx: *usize) ![]u8 {
    var i = idx.*;
    if (i >= tex.len or tex[i] != '[') return A.alloc(u8, 0);
    i += 1;
    const start = i;
    var depth: usize = 1;
    while (i < tex.len and depth > 0) {
        if (tex[i] == '[') depth += 1 else if (tex[i] == ']') depth -= 1;
        i += 1;
    }
    idx.* = i;
    return A.dupe(u8, tex[start .. i - 1]);
}

// -------------------------
// Unit tests (with helpful failure dumps)
// -------------------------

fn assertContains(hay: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, hay, needle) == null) {
        std.debug.print(
            "\nASSERT CONTAINS failed.\n--- needle ---\n{s}\n--- hay ---\n{s}\n--------------\n",
            .{ needle, hay },
        );
        return error.TestUnexpectedResult;
    }
}

test "latex_import: title and author to meta" {
    const tex =
        \\\\title{My Paper}
        \\\\author{Jane Doe}
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importLatexToDcz(A, tex);
    defer A.free(out);

    try assertContains(out, "@meta(title=\"My Paper\") @end");
    try assertContains(out, "@meta(author=\"Jane Doe\") @end");
}

test "latex_import: sections to headings" {
    const tex =
        \\\\section{Intro}
        \\Some text.
        \\\\subsection{Background}
        \\More text.
        \\\\subsubsection{Details}
        \\End.
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importLatexToDcz(A, tex);
    defer A.free(out);

    try assertContains(out, "@heading(level=1) Intro @end");
    try assertContains(out, "@heading(level=2) Background @end");
    try assertContains(out, "@heading(level=3) Details @end");
}

test "latex_import: graphics, verbatim, equation, and paragraphs" {
    const tex =
        \\Here is an intro paragraph.
        \\
        \\\\includegraphics[width=3in]{figs/plot.pdf}
        \\
        \\\\begin{verbatim}
        \\const x = 42;
        \\\\end{verbatim}
        \\
        \\\\begin{equation}
        \\E = mc^2
        \\\\end{equation}
        \\
        \\A final paragraph.
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importLatexToDcz(A, tex);
    defer A.free(out);

    try assertContains(out, "Here is an intro paragraph.\n");
    try assertContains(out, "@image(src=\"figs/plot.pdf\") @end");
    try assertContains(out,
        \\@code(language="")
    );
    try assertContains(out, "const x = 42;");
    try assertContains(out, "@math E = mc^2 @end");
    try assertContains(out, "A final paragraph.\n");
}

test "latex_import: ignores unknown commands and keeps text" {
    const tex =
        \\Some \\unknowncmd{stuff} remains as text.
        \\And \\alpha more text.
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importLatexToDcz(A, tex);
    defer A.free(out);

    try assertContains(out, "Some  remains as text.");
    try assertContains(out, "And  more text.");
}
