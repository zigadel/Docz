const std = @import("std");

// Import core pieces directly to avoid circular imports via root.zig
const Tokenizer = @import("../src/parser/tokenizer.zig");
const Parser = @import("../src/parser/parser.zig");
const Renderer = @import("../src/renderer/html.zig");

/// Minimal HTTP-ish response struct for the server layer to use.
pub const Response = struct {
    status_code: u16,
    mime: []const u8,
    body: []u8, // owned by caller's allocator

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

/// Render a `.dcz` document (as bytes) to HTML (owned slice).
pub fn renderDoczToHtml(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const tokens = try Tokenizer.tokenize(input, allocator);
    defer {
        // Free any token-owned lexemes before freeing the slice
        Tokenizer.freeTokens(allocator, tokens);
        allocator.free(tokens);
    }

    var ast = try Parser.parse(tokens, allocator);
    defer ast.deinit();

    return try Renderer.renderHTML(&ast, allocator);
}

/// Read a `.dcz` file from disk and render it to HTML.
/// Returns an owned HTML slice.
pub fn renderFileToHtml(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);

    _ = try file.readAll(buf);
    return try renderDoczToHtml(allocator, buf);
}

/// Basic router that decides how to respond to a request path.
/// For now:
///   - `/`               → renders provided `default_docz_path`
///   - `/*.dcz`          → renders that file
///   - anything else     → 404
pub fn route(
    allocator: std.mem.Allocator,
    path: []const u8,
    default_docz_path: []const u8,
) !Response {
    if (std.mem.eql(u8, path, "/")) {
        const html = try renderFileToHtml(allocator, default_docz_path);
        return Response{
            .status_code = 200,
            .mime = "text/html",
            .body = html,
        };
    }

    if (std.mem.endsWith(u8, path, ".dcz")) {
        // strip leading slash
        const fs_path = if (path.len > 0 and path[0] == '/') path[1..] else path;
        const html = try renderFileToHtml(allocator, fs_path);
        return Response{
            .status_code = 200,
            .mime = "text/html",
            .body = html,
        };
    }

    // TODO: later we'll serve static assets (client JS/CSS) here too.
    const msg = "Not Found";
    const body = try allocator.dupe(u8, msg);
    return Response{
        .status_code = 404,
        .mime = "text/plain",
        .body = body,
    };
}

// ─────────────────────────────────────────────────────────────
// 🧪 Tests
// ─────────────────────────────────────────────────────────────

test "renderDoczToHtml: basic doc renders expected pieces" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    const input =
        \\@meta(title="Hello")
        \\@heading(level=1) Welcome @end
        \\@code(language="zig")
        \\const x = 7;
        \\@end
    ;

    const html = try renderDoczToHtml(alloc, input);
    defer alloc.free(html);

    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<title>Hello</title>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h1>Welcome</h1>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "const x = 7;"));
}

test "renderFileToHtml: writes a temp file and renders it" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    // Create a temp .dcz file in the cwd. Use a unique-ish name.
    const filename = "handler_test_temp.dcz";
    {
        var f = try std.fs.cwd().createFile(filename, .{ .read = true, .truncate = true });
        defer f.close();

        const content =
            \\@meta(title="TempDoc")
            \\@heading(level=2) Hi From File @end
        ;
        _ = try f.write(content);
    }
    defer std.fs.cwd().deleteFile(filename) catch {};

    const html = try renderFileToHtml(alloc, filename);
    defer alloc.free(html);

    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<title>TempDoc</title>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h2>Hi From File</h2>"));
}

test "route: / returns HTML for default_docz_path; 404 for unknowns" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    const filename = "handler_route_default.dcz";
    {
        var f = try std.fs.cwd().createFile(filename, .{ .read = true, .truncate = true });
        defer f.close();

        const content =
            \\@meta(title="IndexDoc")
            \\@heading(level=1) Index @end
        ;
        _ = try f.write(content);
    }
    defer std.fs.cwd().deleteFile(filename) catch {};

    // Root route
    var resp = try route(alloc, "/", filename);
    defer resp.deinit(alloc);
    try std.testing.expectEqual(@as(u16, 200), resp.status_code);
    try std.testing.expect(std.mem.eql(u8, resp.mime, "text/html"));
    try std.testing.expect(std.mem.containsAtLeast(u8, resp.body, 1, "<title>IndexDoc</title>"));

    // 404 route
    var not_found = try route(alloc, "/nope", filename);
    defer not_found.deinit(alloc);
    try std.testing.expectEqual(@as(u16, 404), not_found.status_code);
    try std.testing.expect(std.mem.eql(u8, not_found.mime, "text/plain"));
    try std.testing.expect(std.mem.containsAtLeast(u8, not_found.body, 1, "Not Found"));
}

test "route: /foo.dcz renders that explicit file" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    const fname = "explicit_file.dcz";
    {
        var f = try std.fs.cwd().createFile(fname, .{ .read = true, .truncate = true });
        defer f.close();

        const content =
            \\@meta(title="Explicit")
            \\@heading(level=3) Explicit Route @end
        ;
        _ = try f.write(content);
    }
    defer std.fs.cwd().deleteFile(fname) catch {};

    var resp = try route(alloc, "/explicit_file.dcz", "ignored-for-this-test.dcz");
    defer resp.deinit(alloc);

    try std.testing.expectEqual(@as(u16, 200), resp.status_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, resp.body, 1, "<title>Explicit</title>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, resp.body, 1, "<h3>Explicit Route</h3>"));
}
