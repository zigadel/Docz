const std = @import("std");
const docz = @import("docz");

// internal converter modules from build.zig
const latex_import = @import("latex_import");
const latex_export = @import("latex_export");

// ── helpers ──────────────────────────────────────────────────────────────────

fn trimRightSpaces(line: []const u8) []const u8 {
    return std.mem.trimRight(u8, line, " \t\r");
}

/// Normalize LaTeX for comparison:
/// - Trim trailing spaces per line
/// - Collapse 3+ consecutive newlines → 2 newlines
/// - Trim leading/trailing blank lines
/// - Ensure single trailing newline
fn normalizeLatex(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var tmp = std.ArrayList(u8).init(alloc);
    defer tmp.deinit();

    // 1) trim trailing spaces line-by-line
    var it = std.mem.tokenizeScalar(u8, s, '\n');
    var first_line = true;
    while (it.next()) |line| {
        const t = trimRightSpaces(line);
        if (!first_line) try tmp.append('\n');
        try tmp.appendSlice(t);
        first_line = false;
    }

    // 2) collapse >2 newlines → exactly 2
    var out = std.ArrayList(u8).init(alloc);
    var i: usize = 0;
    var nl_count: usize = 0;
    while (i < tmp.items.len) : (i += 1) {
        const c = tmp.items[i];
        if (c == '\n') {
            nl_count += 1;
            if (nl_count <= 2) try out.append('\n');
        } else {
            nl_count = 0;
            try out.append(c);
        }
    }

    // 3) trim leading/trailing newlines
    var start: usize = 0;
    while (start < out.items.len and out.items[start] == '\n') start += 1;

    var end: usize = out.items.len;
    while (end > start and out.items[end - 1] == '\n') end -= 1;

    // 4) build final buffer; deinit 'out' to avoid leaks
    var final_buf = std.ArrayList(u8).init(alloc);
    if (end > start) try final_buf.appendSlice(out.items[start..end]);
    try final_buf.append('\n');
    out.deinit();

    return final_buf.toOwnedSlice();
}

// ── tests ────────────────────────────────────────────────────────────────────

test "integration: LaTeX ↔ DCZ round-trip via AST (baseline sample)" {
    // Use plain strings + '\n' to avoid confusion with Zig's '\\' line-prefix macro.
    const tex_input =
        \\\title{Roundtrip Spec}
        \\\author{Docz}
        \\
        \\\section{Intro}
        \\Hello world paragraph.
        \\
        \\\subsection{Code}
        \\\begin{verbatim}
        \\const x = 1;
        \\\end{verbatim}
        \\
        \\\begin{equation}
        \\E = mc^2
        \\\end{equation}
        \\
        \\\includegraphics{img/logo.png}
        \\
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    // 1) LaTeX → DCZ
    const dcz = try latex_import.importLatexToDcz(A, tex_input);
    defer A.free(dcz);

    // 2) DCZ → tokens → AST
    const tokens = try docz.Tokenizer.tokenize(dcz, A);
    defer {
        docz.Tokenizer.freeTokens(A, tokens);
        A.free(tokens);
    }
    var ast = try docz.Parser.parse(tokens, A);
    defer ast.deinit();

    // 3) AST → LaTeX
    const tex_output = try latex_export.exportAstToLatex(&ast, A);
    defer A.free(tex_output);

    // 4) Normalize + compare
    const n_in = try normalizeLatex(A, tex_input);
    defer A.free(n_in);
    const n_out = try normalizeLatex(A, tex_output);
    defer A.free(n_out);

    try std.testing.expectEqualStrings(n_in, n_out);
}

test "integration: heading level clamp (>=4 → \\subsubsection{})" {
    const tex_input =
        \\\title{Clamp}
        \\
        \\\section{Top}
        \\Para.
        \\
        \\\subsubsection{Deep A}
        \\\subsubsection{Deep B}
        \\
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const dcz = try latex_import.importLatexToDcz(A, tex_input);
    defer A.free(dcz);

    const tokens = try docz.Tokenizer.tokenize(dcz, A);
    defer {
        docz.Tokenizer.freeTokens(A, tokens);
        A.free(tokens);
    }
    var ast = try docz.Parser.parse(tokens, A);
    defer ast.deinit();

    const tex_output = try latex_export.exportAstToLatex(&ast, A);
    defer A.free(tex_output);

    try std.testing.expect(std.mem.indexOf(u8, tex_output, "\\section{Top}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex_output, "\\subsubsection{Deep A}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex_output, "\\subsubsection{Deep B}") != null);

    const n_in = try normalizeLatex(A, tex_input);
    defer A.free(n_in);
    const n_out = try normalizeLatex(A, tex_output);
    defer A.free(n_out);
    try std.testing.expectEqualStrings(n_in, n_out);
}
