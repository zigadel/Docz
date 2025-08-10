const std = @import("std");
const docz = @import("docz");

// internal converters (wired via build.zig)
const html_import = @import("html_import");
const html_export = @import("html_export");
const md_import = @import("md_import");
const md_export = @import("md_export");
const latex_import = @import("latex_import");
const latex_export = @import("latex_export");

pub const Kind = enum { dcz, md, html, tex };

fn detectKindFromPath(p: []const u8) ?Kind {
    const ext = std.fs.path.extension(p);
    if (ext.len == 0) return null;
    if (std.ascii.eqlIgnoreCase(ext, ".dcz")) return .dcz;
    if (std.ascii.eqlIgnoreCase(ext, ".md")) return .md;
    if (std.ascii.eqlIgnoreCase(ext, ".html") or std.ascii.eqlIgnoreCase(ext, ".htm")) return .html;
    if (std.ascii.eqlIgnoreCase(ext, ".tex")) return .tex;
    return null;
}

fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    return try f.readToEndAlloc(alloc, 1 << 26);
}

fn writeFile(path: []const u8, data: []const u8) !void {
    const cwd = std.fs.cwd();
    if (std.fs.path.dirname(path)) |dirpart| {
        try cwd.makePath(dirpart);
    }
    var f = try cwd.createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}

pub fn run(alloc: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const usage =
        "Usage: docz convert <input.{dcz|md|html|htm|tex}> [--to|-t <output.{dcz|md|html|tex}>]\n";

    const in_path = it.next() orelse {
        std.debug.print("{s}", .{usage});
        return error.Invalid;
    };

    // parse flags: --to / -t
    var out_path: ?[]const u8 = null;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--to") or std.mem.eql(u8, arg, "-t")) {
            out_path = it.next() orelse {
                std.debug.print("{s}", .{"convert: --to requires a value\n"});
                return error.Invalid;
            };
        } else {
            std.debug.print("convert: unknown arg: {s}\n", .{arg});
            return error.Invalid;
        }
    }

    const in_kind = detectKindFromPath(in_path) orelse {
        std.debug.print("convert: unsupported input type: {s}\n", .{in_path});
        return error.Invalid;
    };

    const input = readFileAlloc(alloc, in_path) catch |e| {
        // Leak-safe cwd reporting
        const cwd_buf: ?[]u8 = std.fs.cwd().realpathAlloc(alloc, ".") catch null;
        defer if (cwd_buf) |buf| alloc.free(buf);
        const cwd = cwd_buf orelse "<?>";

        std.debug.print("convert: failed to read '{s}' (cwd: {s}): {s}\n", .{ in_path, cwd, @errorName(e) });
        return e;
    };
    defer alloc.free(input);

    var out_buf: []u8 = &[_]u8{};
    defer if (out_buf.len != 0 and out_buf.ptr != input.ptr) alloc.free(out_buf);

    if (in_kind == .dcz) {
        // DCZ -> AST
        const tokens = try docz.Tokenizer.tokenize(input, alloc);
        defer {
            // If Tokenizer allocates per-token payloads, free them first, then the array.
            docz.Tokenizer.freeTokens(alloc, tokens);
            alloc.free(tokens);
        }

        var ast = try docz.Parser.parse(tokens, alloc);
        defer ast.deinit();

        const out_kind = if (out_path) |p| detectKindFromPath(p) else null;

        if (out_kind == null or out_kind.? == .dcz) {
            out_buf = try alloc.dupe(u8, input);
        } else switch (out_kind.?) {
            .md => out_buf = try md_export.exportAstToMarkdown(&ast, alloc),
            .html => out_buf = try html_export.exportHtml(&ast, alloc), // symbol in src/convert/html/export.zig
            .tex => out_buf = try latex_export.exportAstToLatex(&ast, alloc),
            .dcz => unreachable,
        }
    } else {
        // Import -> DCZ
        switch (in_kind) {
            .md => out_buf = try md_import.importMarkdownToDcz(alloc, input),
            .html => out_buf = try html_import.importHtmlToDcz(alloc, input),
            .tex => out_buf = try latex_import.importLatexToDcz(alloc, input),
            .dcz => unreachable,
        }
    }

    if (out_path) |p| {
        if (detectKindFromPath(p) == null) {
            std.debug.print("convert: unsupported output type: {s}\n", .{p});
            return error.Invalid;
        }
        try writeFile(p, out_buf);
    } else {
        // Print buffer (Zig 0.15 dev: use debug.print for portability)
        std.debug.print("{s}", .{out_buf});
    }
}

test "convert.detectKindFromPath: basic mapping" {
    try std.testing.expect(detectKindFromPath("a.dcz") == .dcz);
    try std.testing.expect(detectKindFromPath("a.MD") == .md);
    try std.testing.expect(detectKindFromPath("a.html") == .html);
    try std.testing.expect(detectKindFromPath("a.HTM") == .html);
    try std.testing.expect(detectKindFromPath("a.tex") == .tex);
    try std.testing.expect(detectKindFromPath("noext") == null);
}
