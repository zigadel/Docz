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

/// True iff there is a directive introducer at position `i`.
/// A directive must start at the beginning of the file or immediately after '\n',
/// and be followed by an alphabetic name (e.g. "@meta", "@end").
fn isDirectiveStart(input: []const u8, i: usize) bool {
    if (i >= input.len) return false;
    if (input[i] != '@') return false;
    if (i > 0 and input[i - 1] != '\n') return false;
    if (i + 1 >= input.len) return false;
    return std.ascii.isAlphabetic(input[i + 1]);
}

/// Tokenize `.dcz` input into an array of tokens.
/// Caller owns returned slice; must free allocated lexemes where `is_allocated=true`.
pub fn tokenize(input: []const u8, allocator: std.mem.Allocator) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);

    var i: usize = 0;

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
        const c = input[i];

        // 1) Escaped literal '@' — "@@" + word
        if (c == '@' and i + 1 < input.len and input[i + 1] == '@') {
            i += 2; // skip "@@"
            const start = i;
            while (i < input.len and !std.ascii.isWhitespace(input[i])) : (i += 1) {}
            const word = input[start..i];

            const combined = try std.fmt.allocPrint(allocator, "@{s}", .{word});
            try tokens.append(.{
                .kind = .Content,
                .lexeme = combined,
                .is_allocated = true,
            });
            continue;
        }

        // 2) Recognize "@end" ANYWHERE (needed for inline-closed directives like @heading(...) Title @end)
        if (c == '@' and i + 4 <= input.len and std.mem.eql(u8, input[i .. i + 4], "@end")) {
            try tokens.append(.{ .kind = .BlockEnd, .lexeme = input[i .. i + 4] });
            i += 4;
            continue;
        }

        // 3) Recognize other directives ONLY at start-of-line (allowing indentation with spaces/tabs)
        if (c == '@') {
            // Check start-of-line with optional indentation: walk back over spaces/tabs
            var j = i;
            while (j > 0 and (input[j - 1] == ' ' or input[j - 1] == '\t')) : (j -= 1) {}
            const at_sol = (j == 0) or (input[j - 1] == '\n' or input[j - 1] == '\r');

            if (at_sol) {
                const d_start = i;
                i += 1; // skip '@'

                // read directive name (alphabetic)
                while (i < input.len and std.ascii.isAlphabetic(input[i])) : (i += 1) {}
                const directive = input[d_start..i];

                // bare "@" fallback
                if (directive.len == 1) {
                    try tokens.append(.{ .kind = .Content, .lexeme = "@" });
                    continue;
                }

                try tokens.append(.{ .kind = .Directive, .lexeme = directive });

                // Optional parameter list: (...) — robust to EOF / malformed input
                if (i < input.len and input[i] == '(') {
                    i += 1; // skip '('

                    // Inner loop progress guard
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

                        // Gracefully break if we hit EOF before ')'
                        if (i >= input.len) break;

                        // comma separators
                        if (input[i] == ',') {
                            i += 1;
                            continue;
                        }

                        // Parameter key (alphabetic)
                        const key_start = i;
                        while (i < input.len and std.ascii.isAlphabetic(input[i])) : (i += 1) {}
                        if (i > key_start) {
                            try tokens.append(.{
                                .kind = .ParameterKey,
                                .lexeme = input[key_start..i],
                            });
                        } else {
                            // If there's neither key nor comma nor ')', consume one char
                            if (i < input.len and input[i] != ')' and input[i] != ',') {
                                i += 1;
                            }
                            continue;
                        }

                        // '=' and value
                        if (i < input.len and input[i] == '=') {
                            i += 1;

                            // quoted string value
                            if (i < input.len and input[i] == '"') {
                                i += 1; // skip opening quote
                                const str_start = i;

                                // Simple quoted read (no escapes yet)
                                while (i < input.len and input[i] != '"') : (i += 1) {}

                                // If EOF before closing quote, take to EOF
                                const str_end = if (i < input.len) i else input.len;
                                try tokens.append(.{
                                    .kind = .ParameterValue,
                                    .lexeme = input[str_start..str_end],
                                });

                                // Skip closing quote if present
                                if (i < input.len and input[i] == '"') i += 1;
                            } else {
                                // unquoted value: read until whitespace, ')' or ','
                                const v_start = i;
                                while (i < input.len) : (i += 1) {
                                    const ch = input[i];
                                    if (std.ascii.isWhitespace(ch) or ch == ')' or ch == ',') break;
                                }
                                if (i > v_start) {
                                    try tokens.append(.{
                                        .kind = .ParameterValue,
                                        .lexeme = input[v_start..i],
                                    });
                                }
                            }
                        }

                        // Trailing commas are consumed at top; loop continues
                    }

                    // consume closing ')', if any
                    if (i < input.len and input[i] == ')') i += 1;
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

        // 6) Raw content until newline OR a directive-start '@'
        const content_start = i;
        while (i < input.len) : (i += 1) {
            const ch = input[i];
            if (ch == '\n' or ch == '\r') break;

            if (ch == '@') {
                // NEW: break on '@@' so outer loop can emit the literal-@ token
                if (i + 1 < input.len and input[i + 1] == '@') break;

                // stop if this is "@end"
                if (i + 4 <= input.len and std.mem.eql(u8, input[i .. i + 4], "@end")) break;

                // or if it's a start-of-line directive (allowing indentation):
                var k = i;
                while (k > 0 and (input[k - 1] == ' ' or input[k - 1] == '\t')) : (k -= 1) {}
                const sol = (k == 0) or (input[k - 1] == '\n' or input[k - 1] == '\r');
                if (sol) break;
            }
        }
        if (i > content_start) {
            try tokens.append(.{
                .kind = .Content,
                .lexeme = input[content_start..i],
            });
        }
        // newline will be handled on next loop iteration
    }

    return tokens.toOwnedSlice();
}

/// Free all heap allocations in token list.
pub fn freeTokens(allocator: std.mem.Allocator, tokens: []Token) void {
    for (tokens) |t| {
        if (t.is_allocated) allocator.free(t.lexeme);
    }
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
