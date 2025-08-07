const std = @import("std");
const docz = @import("docz");

pub const _ = true;

test "🔍 VISIBLE TEST: tokenizer integration test" {
    try std.testing.expect(false); // Force fail so you can see it ran
}

test "integration: tokenizer produces correct tokens from .dcz input" {
    const input =
        \\@heading(level=1) Hello, Docz! @end
        \\This is a **test** of the tokenizer.
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const tokens = try docz.Tokenizer.tokenize(input, allocator);
    defer docz.Tokenizer.freeTokens(allocator, tokens);

    std.debug.print("📦 Tokenizer produced {d} tokens:\n", .{tokens.len});
    for (tokens, 0..) |tok, i| {
        std.debug.print("  [{d}] {s} : {s}\n", .{ i, @tagName(tok.kind), tok.lexeme });
    }

    try std.testing.expect(tokens.len > 2);
}

test "tokenizer: placeholder" {
    const allocator = std.testing.allocator;
    const input = "Hello, *world!*";
    const tokens = try docz.Tokenizer.tokenize(input, allocator);
    defer docz.Tokenizer.freeTokens(allocator, tokens);

    try std.testing.expect(tokens.len > 0);

    // TEMP: Force fail to verify this runs
    try std.testing.expect(tokens.len == 999); // should fail
}

test "force fail" {
    try std.testing.expect(false); // just for test
}
