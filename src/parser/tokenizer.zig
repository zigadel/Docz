const std = @import("std");

pub const TokenType = enum {
    Directive,
    ParameterKey,
    ParameterValue,
    Content,
    BlockEnd,
};

pub const Token = struct {
    kind: TokenType,
    lexeme: []const u8,
    is_allocated: bool = false, // track ownership for @@ case
};

/// Optional config (reserved for future knobs).
/// Use `tokenize()` for the default behavior; use `tokenizeWith()` if/when
/// you want to expose options without changing the public signature.
pub const TokenizerConfig = struct {
    /// Directives (with leading '@') that start a fenced raw block.
    fenced_directives: []const []const u8 = &.{ "@code", "@math", "@style", "@css" },

    pub fn isFenced(self: *const TokenizerConfig, dir: []const u8) bool {
        for (self.fenced_directives) |d| {
            if (std.mem.eql(u8, d, dir)) return true;
        }
        return false;
    }
};

/// Public, backward-compatible API used across the repo/tests.
pub fn tokenize(input: []const u8, allocator: std.mem.Allocator) ![]Token {
    return tokenizeWith(input, allocator, .{});
}

/// Extended API (kept internal for now) that accepts options.
pub fn tokenizeWith(input: []const u8, allocator: std.mem.Allocator, config: TokenizerConfig) ![]Token {
    const A = allocator;

    var tokens = std.ArrayList(Token){};
    errdefer tokens.deinit(A);

    var i: usize = 0;

    // Skip UTF-8 BOM if present
    if (input.len >= 3 and input[0] == 0xEF and input[1] == 0xBB and input[2] == 0xBF) {
        i = 3;
    }

    // Fence state: when non-empty, we are inside a raw block until a line that is "@end"
    // or ends with "@end" (after optional whitespace).
    var fence_name: []const u8 = "";

    // Global no-progress guard (defensive)
    var prev_i: usize = ~@as(usize, 0);
    var stuck_iters: usize = 0;

    while (i < input.len) : ({
        if (i == prev_i) {
            stuck_iters += 1;
            if (stuck_iters >= 10_000_000) return error.TokenizerStuck;
        } else {
            prev_i = i;
            stuck_iters = 0;
        }
    }) {
        // ── Fenced mode: slurp raw content until a closer appears.
        if (fence_name.len != 0) {
            // Skip a single leading newline so fenced content begins on its own line.
            if (i < input.len) {
                if (input[i] == '\r') {
                    if (i + 1 < input.len and input[i + 1] == '\n') {
                        i += 2;
                    } else {
                        i += 1;
                    }
                } else if (input[i] == '\n') {
                    i += 1;
                }
            }

            // Optional heuristic: for math blocks only, strip leading indentation on the first content line.
            if (std.mem.eql(u8, fence_name, "@math")) {
                while (i < input.len and (input[i] == ' ' or input[i] == '\t')) : (i += 1) {}
            }

            const content_start = i;

            while (i < input.len) {
                const eol = lineEnd(input, i);
                const line = input[i..eol];

                // Case 1: whole trimmed line is "@end"
                if (trimmedEq(line, "@end")) {
                    if (content_start < i) {
                        try tokens.append(A, .{ .kind = .Content, .lexeme = input[content_start..i] });
                    }
                    try tokens.append(A, .{ .kind = .BlockEnd, .lexeme = "@end" });
                    i = if (eol < input.len and input[eol] == '\n') eol + 1 else eol;
                    fence_name = "";
                    break;
                }

                // Case 2: inline closer at end-of-line: "...something... @end[WS]"
                if (std.mem.indexOf(u8, line, "@end")) |pos| {
                    const after = line[pos..];
                    if (trimmedEq(after, "@end")) {
                        // trim any spaces/tabs immediately before "@end"
                        var cut_abs = i + pos;
                        while (cut_abs > content_start and (input[cut_abs - 1] == ' ' or input[cut_abs - 1] == '\t')) {
                            cut_abs -= 1;
                        }

                        if (content_start < cut_abs) {
                            try tokens.append(A, .{ .kind = .Content, .lexeme = input[content_start..cut_abs] });
                        }
                        try tokens.append(A, .{ .kind = .BlockEnd, .lexeme = "@end" });
                        // consume the rest of this line including newline
                        i = if (eol < input.len and input[eol] == '\n') eol + 1 else eol;
                        fence_name = "";
                        break;
                    }
                }

                // Not a closer: advance to next line
                i = if (eol < input.len and input[eol] == '\n') eol + 1 else eol;
            }

            // EOF with no @end: emit remainder and exit fence
            if (fence_name.len != 0 and content_start < input.len) {
                try tokens.append(A, .{ .kind = .Content, .lexeme = input[content_start..input.len] });
                fence_name = "";
                i = input.len;
            }
            continue;
        }

        const c = input[i];

        // 1) Escaped literal '@' — "@@" + word → emit as Content("@word")
        if (c == '@' and i + 1 < input.len and input[i + 1] == '@') {
            i += 2; // skip "@@"
            const start = i;
            while (i < input.len and !std.ascii.isWhitespace(input[i])) : (i += 1) {}
            const word = input[start..i];

            const combined = try std.fmt.allocPrint(A, "@{s}", .{word});
            try tokens.append(A, .{
                .kind = .Content,
                .lexeme = combined,
                .is_allocated = true,
            });
            continue;
        }

        // 2) Standalone @end: only when the rest of this line (trimmed) is exactly "@end"
        if (c == '@' and i + 4 <= input.len and std.mem.eql(u8, input[i .. i + 4], "@end")) {
            const eol = lineEnd(input, i);
            if (trimmedEq(input[i..eol], "@end")) {
                try tokens.append(A, .{ .kind = .BlockEnd, .lexeme = "@end" });
                i = if (eol < input.len and input[eol] == '\n') eol + 1 else eol;
                continue;
            }
            // else: literal "`@end`" in prose → fall through
        }

        // 3) Directives at SOL (allow leading spaces/tabs)
        if (c == '@') {
            var j = i;
            while (j > 0 and (input[j - 1] == ' ' or input[j - 1] == '\t')) : (j -= 1) {}
            const at_sol = (j == 0) or (input[j - 1] == '\n' or input[j - 1] == '\r');

            if (at_sol) {
                const d_start = i;
                i += 1; // skip '@'

                // Allow letters, digits, '_' and '-' in directive identifiers.
                while (i < input.len) : (i += 1) {
                    const ch = input[i];
                    if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-')) break;
                }
                const directive_full = input[d_start..i]; // e.g. "@meta", "@style-def"

                if (directive_full.len == 1) {
                    try tokens.append(A, .{ .kind = .Content, .lexeme = "@" });
                    continue;
                }

                try tokens.append(A, .{ .kind = .Directive, .lexeme = directive_full });

                // Optional parameter list: (...)
                if (i < input.len and input[i] == '(') {
                    i += 1;

                    var inner_prev: usize = ~@as(usize, 0);
                    var inner_stuck: usize = 0;

                    while (i < input.len and input[i] != ')') : ({
                        if (i == inner_prev) {
                            inner_stuck += 1;
                            if (inner_stuck >= 10_000_000) return error.TokenizerStuck;
                        } else {
                            inner_prev = i;
                            inner_stuck = 0;
                        }
                    }) {
                        // skip whitespace
                        while (i < input.len and std.ascii.isWhitespace(input[i])) : (i += 1) {}
                        if (i >= input.len) break;

                        // commas
                        if (input[i] == ',') {
                            i += 1;
                            continue;
                        }

                        // key: allow letters, digits, '_' and '-' (to match directive style)
                        const key_start = i;
                        while (i < input.len) : (i += 1) {
                            const ch = input[i];
                            if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-')) break;
                        }
                        if (i > key_start) {
                            try tokens.append(A, .{ .kind = .ParameterKey, .lexeme = input[key_start..i] });
                        } else {
                            // skip one char to avoid infinite loop if malformed
                            if (i < input.len and input[i] != ')' and input[i] != ',') i += 1;
                            continue;
                        }

                        // '=' and value
                        if (i < input.len and input[i] == '=') {
                            i += 1;

                            if (i < input.len and input[i] == '"') {
                                i += 1; // opening quote
                                const str_start = i;
                                while (i < input.len) : (i += 1) {
                                    if (input[i] == '"') break;
                                }
                                const str_end = if (i < input.len) i else input.len;
                                try tokens.append(A, .{ .kind = .ParameterValue, .lexeme = input[str_start..str_end] });
                                if (i < input.len and input[i] == '"') i += 1;
                            } else {
                                const v_start = i;
                                while (i < input.len) : (i += 1) {
                                    const ch = input[i];
                                    if (std.ascii.isWhitespace(ch) or ch == ')' or ch == ',') break;
                                }
                                if (i > v_start) {
                                    try tokens.append(A, .{ .kind = .ParameterValue, .lexeme = input[v_start..i] });
                                }
                            }
                        }
                    }
                    if (i < input.len and input[i] == ')') i += 1;
                }

                // Fence-opening directives (configurable)
                if (config.isFenced(directive_full)) {
                    fence_name = directive_full; // any non-empty marker works
                }

                continue;
            }
        }

        // 4) Line comments starting with "#:" (to end of line)
        if (c == '#' and i + 1 < input.len and input[i + 1] == ':') {
            while (i < input.len and input[i] != '\n') : (i += 1) {}
            continue;
        }

        // 5) Whitespace: skip (includes newlines)
        if (std.ascii.isWhitespace(c)) {
            i += 1;
            continue;
        }

        // 6) Raw content until newline OR a standalone "@end" OR a SOL directive
        const content_start = i;
        while (i < input.len) : (i += 1) {
            const ch = input[i];
            if (ch == '\n' or ch == '\r') break;

            if (ch == '@') {
                // Break on "@@" so outer loop can emit the literal-@ token
                if (i + 1 < input.len and input[i + 1] == '@') break;

                // If remainder of this line (trimmed) is exactly "@end", stop here
                const eol2 = lineEnd(input, i);
                if (eol2 > i and trimmedEq(input[i..eol2], "@end")) break;

                // If it's a start-of-line directive (allowing indentation), let outer loop handle it.
                var k = i;
                while (k > 0 and (input[k - 1] == ' ' or input[k - 1] == '\t')) : (k -= 1) {}
                const sol = (k == 0) or (input[k - 1] == '\n' or input[k - 1] == '\r');
                if (sol) break;
            }
        }
        if (i > content_start) {
            try tokens.append(A, .{ .kind = .Content, .lexeme = input[content_start..i] });
        }
        // newline (if any) handled next iteration
    }

    return try tokens.toOwnedSlice(A);
}

/// Free all heap allocations in token list.
pub fn freeTokens(allocator: std.mem.Allocator, tokens: []Token) void {
    for (tokens) |t| {
        if (t.is_allocated) allocator.free(t.lexeme);
    }
}

// ── helpers ─────────────────────────────────────────────────

/// Return index of end-of-line (position of '\n' or input.len).
fn lineEnd(input: []const u8, pos: usize) usize {
    var j = pos;
    while (j < input.len and input[j] != '\n') : (j += 1) {}
    return j;
}

/// Compare slice (trimmed of spaces/tabs/CR) with needle.
fn trimmedEq(slice: []const u8, needle: []const u8) bool {
    const t = std.mem.trim(u8, slice, " \t\r");
    return std.mem.eql(u8, t, needle);
}

// ----------------------
// Tests
// ----------------------
test "Tokenize escape sequence @@ as literal @" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    var allocator = gpa.allocator();

    const input = "Contact @@support@example.com";
    const toks = try tokenize(input, allocator);
    defer {
        freeTokens(allocator, toks);
        allocator.free(toks);
    }

    try std.testing.expectEqual(@as(usize, 2), toks.len);
    try std.testing.expectEqualStrings("Contact ", toks[0].lexeme);
    try std.testing.expectEqualStrings("@support@example.com", toks[1].lexeme);
}

test "Unclosed parameter list does not hang" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const input =
        \\@meta(title="Hello"
        \\Content after
    ;

    const toks = try tokenize(input, A);
    defer {
        freeTokens(A, toks);
        A.free(toks);
    }

    // We at least see the directive and some content; exact count is not strict.
    try std.testing.expect(toks.len >= 2);
}

test "Fenced code block captures raw until standalone or inline @end" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const input =
        \\@code(language="txt")
        \\line 1
        \\line 2 @end
        \\After
    ;

    const toks = try tokenize(input, A);
    defer {
        freeTokens(A, toks);
        A.free(toks);
    }

    // Expect: Directive, ParamKey, ParamValue, Content("line 1\nline 2"), BlockEnd, Content("After")
    try std.testing.expect(toks.len >= 5);
    try std.testing.expect(toks[0].kind == .Directive);
    try std.testing.expect(toks[3].kind == .Content);
    try std.testing.expect(std.mem.indexOf(u8, toks[3].lexeme, "line 2") != null);
    // Ensure "@end" not included in content
    try std.testing.expect(std.mem.indexOf(u8, toks[3].lexeme, "@end") == null);
}

test "Inline `@end` in prose does not become BlockEnd (outside fence)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const input =
        \\This paragraph mentions `@end` and continues.
        \\@heading(level=2) Title
        \\@end
    ;

    const toks = try tokenize(input, A);
    defer {
        freeTokens(A, toks);
        A.free(toks);
    }

    var found_inline = false;
    var found_blockend = false;
    for (toks) |t| {
        if (t.kind == .Content and std.mem.indexOf(u8, t.lexeme, "`@end`") != null) found_inline = true;
        if (t.kind == .BlockEnd) found_blockend = true;
    }
    try std.testing.expect(found_inline);
    try std.testing.expect(found_blockend);
}

test "Alias @css fences like @style" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const input =
        \\@css()
        \\p { color: green }
        \\@end
    ;

    const toks = try tokenize(input, A);
    defer {
        freeTokens(A, toks);
        A.free(toks);
    }

    // Expect: Directive(@css), params, Content, BlockEnd
    var saw_content = false;
    var saw_blockend = false;
    for (toks) |t| {
        if (t.kind == .Content and std.mem.indexOf(u8, t.lexeme, "color: green") != null) saw_content = true;
        if (t.kind == .BlockEnd) saw_blockend = true;
    }
    try std.testing.expect(saw_content);
    try std.testing.expect(saw_blockend);
}

test "Directive names and param keys may contain '-'" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const input =
        \\@style-def(theme-name="default")
        \\.x{}
        \\@end
    ;

    const toks = try tokenize(input, A);
    defer {
        freeTokens(A, toks);
        A.free(toks);
    }

    // First token should be a Directive whose lexeme includes "@style-def"
    try std.testing.expect(toks.len >= 3);
    try std.testing.expect(toks[0].kind == .Directive);
    try std.testing.expect(std.mem.eql(u8, toks[0].lexeme, "@style-def"));
    // ParameterKey should include '-'
    var saw_key = false;
    for (toks) |t| {
        if (t.kind == .ParameterKey and std.mem.eql(u8, t.lexeme, "theme-name")) saw_key = true;
    }
    try std.testing.expect(saw_key);
}
