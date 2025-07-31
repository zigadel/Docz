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
    is_allocated: bool = false, // ✅ track ownership
};

/// Tokenize `.dcz` input into an array of tokens.
/// Caller owns returned slice; must free allocated lexemes where `is_allocated=true`.
pub fn tokenize(input: []const u8, allocator: std.mem.Allocator) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);

    var i: usize = 0;
    while (i < input.len) {
        const c = input[i];

        // Skip whitespace
        if (std.ascii.isWhitespace(c)) {
            i += 1;
            continue;
        }

        // Handle comments
        if (c == '#' and i + 1 < input.len and input[i + 1] == ':') {
            while (i < input.len and input[i] != '\n') : (i += 1) {}
            continue;
        }

        // ✅ Escape sequence @@ → literal '@' + rest of word
        if (c == '@' and i + 1 < input.len and input[i + 1] == '@') {
            i += 2; // skip '@@'
            const start = i;

            // Grab the rest of the word
            while (i < input.len and !std.ascii.isWhitespace(input[i])) : (i += 1) {}
            const word = input[start..i];

            const combined = try std.fmt.allocPrint(allocator, "@{s}", .{word});
            try tokens.append(Token{
                .kind = .Content,
                .lexeme = combined,
                .is_allocated = true,
            });
            continue;
        }

        // Handle directives
        if (c == '@') {
            const start = i;
            i += 1;
            while (i < input.len and std.ascii.isAlphabetic(input[i])) : (i += 1) {}
            const directive = input[start..i];

            if (std.mem.eql(u8, directive, "@end")) {
                try tokens.append(Token{ .kind = .BlockEnd, .lexeme = directive });
                continue;
            } else {
                try tokens.append(Token{ .kind = .Directive, .lexeme = directive });
            }

            // Parameters in (...)
            if (i < input.len and input[i] == '(') {
                i += 1;
                while (i < input.len and input[i] != ')') {
                    while (i < input.len and std.ascii.isWhitespace(input[i])) : (i += 1) {}

                    const key_start = i;
                    while (i < input.len and std.ascii.isAlphabetic(input[i])) : (i += 1) {}
                    if (i > key_start) {
                        try tokens.append(Token{
                            .kind = .ParameterKey,
                            .lexeme = input[key_start..i],
                        });
                    }

                    if (i < input.len and input[i] == '=') {
                        i += 1;
                        const value_start = i;

                        if (i < input.len and input[i] == '"') {
                            i += 1;
                            const str_start = i;
                            while (i < input.len and input[i] != '"') : (i += 1) {}
                            try tokens.append(Token{
                                .kind = .ParameterValue,
                                .lexeme = input[str_start..i],
                            });
                            if (i < input.len) i += 1;
                        } else {
                            while (i < input.len and !std.ascii.isWhitespace(input[i]) and input[i] != ')') : (i += 1) {}
                            try tokens.append(Token{
                                .kind = .ParameterValue,
                                .lexeme = input[value_start..i],
                            });
                        }
                    }

                    if (i < input.len and input[i] == ',') {
                        i += 1;
                    }
                }
                if (i < input.len and input[i] == ')') i += 1;
            }

            continue;
        }

        // Raw content
        const content_start = i;
        while (i < input.len and input[i] != '@' and input[i] != '\n') : (i += 1) {}
        if (i > content_start) {
            try tokens.append(Token{
                .kind = .Content,
                .lexeme = input[content_start..i],
            });
        }
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
    const tokens = try tokenize(input, allocator);
    defer {
        freeTokens(allocator, tokens);
        allocator.free(tokens);
    }

    std.debug.print("DEBUG TOKENS (len={}):\n", .{tokens.len});
    for (tokens, 0..) |t, idx| {
        std.debug.print("  {}: kind={any}, lexeme=\"{s}\"\n", .{ idx, t.kind, t.lexeme });
    }

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqualStrings(tokens[0].lexeme, "Contact ");
    try std.testing.expectEqualStrings(tokens[1].lexeme, "@support@example.com");
}
