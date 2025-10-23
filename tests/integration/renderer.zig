const std = @import("std");
const docz = @import("docz");
const html_export = @import("html_export");

pub const _force_test_discovery = true;

test "integration: renderer produces HTML from simple AST" {
    const input =
        \\@heading(level=3) Render Test @end
        \\Code below:
        \\@code(language="zig")
        \\const x = 9;
        \\@end
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const tokens = try docz.Tokenizer.tokenize(input, allocator);
    defer allocator.free(tokens);

    var ast = try docz.Parser.parse(tokens, allocator);
    defer ast.deinit(allocator);

    const html = try html_export.exportHtml(&ast, allocator);
    defer allocator.free(html);

    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h3>Render Test</h3>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "const x = 9;"));
}
