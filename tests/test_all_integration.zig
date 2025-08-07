const std = @import("std");
const docz = @import("docz");

test "integration: tokenizer basic test" {
    const input = "Hello, *world!*";
    const allocator = std.testing.allocator;

    const tokens = try docz.Tokenizer.tokenize(input, allocator);
    defer docz.Tokenizer.freeTokens(allocator, tokens);

    std.debug.print("📦 Integration Test: {d} tokens parsed\n", .{tokens.len});

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const tok = tokens[i];
        std.debug.print("  [{d}] {s} : {s}\n", .{ i, @tagName(tok.kind), tok.lexeme });
    }

    try std.testing.expect(tokens.len > 0);
}
