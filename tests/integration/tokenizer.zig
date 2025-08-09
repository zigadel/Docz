const std = @import("std");
const docz = @import("docz");

test "integration: tokenizer produces correct tokens from .dcz input" {
    const input =
        \\@heading(level=1) Hello, Docz! @end
        \\This is a **test** of the tokenizer.
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const tokens = try docz.Tokenizer.tokenize(input, allocator);
    defer {
        // IMPORTANT: free allocated lexemes first, then the slice itself
        docz.Tokenizer.freeTokens(allocator, tokens);
        allocator.free(tokens);
    }

    std.debug.print("📦 Tokenizer produced {d} tokens:\n", .{tokens.len});
    for (tokens, 0..) |tok, i| {
        std.debug.print("  [{d}] {s} : {s}\n", .{ i, @tagName(tok.kind), tok.lexeme });
    }

    try std.testing.expect(tokens.len > 2);
}
