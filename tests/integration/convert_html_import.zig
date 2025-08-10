const std = @import("std");
const html_import = @import("html_import"); // wired in build.zig

test "integration: HTML import produces expected dcz" {
    const html =
        \\<html><head><title>T</title>
        \\  <meta name="author" content="Docz Team">
        \\</head>
        \\<body><h1>Hi</h1><p>Para</p></body></html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try html_import.importHtmlToDcz(A, html);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "@meta(title=\"T\") @end") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@meta(author=\"Docz Team\") @end") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@heading(level=1) Hi @end") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Para\n") != null);
}

test "integration: images and <pre><code class=language-*> blocks" {
    const html =
        \\<html><body>
        \\  <img src="/img/logo.png" alt="x">
        \\  <pre><code class="language-zig">const x = 42;</code></pre>
        \\</body></html>
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try html_import.importHtmlToDcz(A, html);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "@image(src=\"/img/logo.png\") @end") != null);

    // minimal check for a code block with the right language and body
    try std.testing.expect(std.mem.indexOf(u8, out,
        \\@code(language="zig")
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "const x = 42;") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@end\n") != null);
}
