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

/// Tokenize `.dcz` input into an array of tokens.
/// Caller owns returned slice; must free allocated lexemes where `is_allocated=true`.
pub fn tokenize(input: []const u8, allocator: std.mem.Allocator) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);

    var i: usize = 0;

    // Global no-progress guard (defensive)
    var prev_i: usize = ~@as(usize, 0);
    var stuck_iters: usize = 0;

    while (i < input.len) : ({
        // --- no-progress guard for the outer loop ---
        if (i == prev_i) {
            stuck_iters += 1;
            if (stuck_iters >= 10_000_000) {
                // Fail fast instead of spinning forever.
                return error.TokenizerStuck;
            }
        } else {
            prev_i = i;
            stuck_iters = 0;
        }
    }) {
        const c = input[i];

        // 1) Skip whitespace quickly
        if (std.ascii.isWhitespace(c)) {
            i += 1;
            continue;
        }

        // 2) Line comments starting with "#:" (to end of line)
        if (c == '#' and i + 1 < input.len and input[i + 1] == ':') {
            while (i < input.len and input[i] != '\n') : (i += 1) {}
            continue;
        }

        // 3) Escaped literal '@' — "@@" + word
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

        // 4) Directives: @word or @end
        if (c == '@') {
            const d_start = i;
            i += 1; // skip '@'

            // read directive name (alphabetic)
            const name_start = i;
            while (i < input.len and std.ascii.isAlphabetic(input[i])) : (i += 1) {}
            const directive = input[d_start..i];

            if (std.mem.eql(u8, directive, "@end")) {
                try tokens.append(.{ .kind = .BlockEnd, .lexeme = directive });
                continue;
            } else {
                // If it's just bare "@", treat it as content to be forgiving.
                if (i == name_start) {
                    try tokens.append(.{ .kind = .Content, .lexeme = "@" });
                    continue;
                }
                try tokens.append(.{ .kind = .Directive, .lexeme = directive });
            }

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
                        // to avoid getting stuck on unexpected symbols.
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

        // 5) Raw content until '@' or newline
        const content_start = i;
        while (i < input.len and input[i] != '@' and input[i] != '\n') : (i += 1) {}
        if (i > content_start) {
            try tokens.append(.{
                .kind = .Content,
                .lexeme = input[content_start..i],
            });
        }
        // newline will be skipped by the whitespace branch next loop
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
