const std = @import("std");
const docz = @import("docz");

// internal converters (build.zig already wires these into the CLI root module)
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

    var buf: [16]u8 = undefined;
    const e = std.ascii.lowerString(&buf, ext) catch ext;

    if (std.mem.eql(u8, e, ".dcz")) return .dcz;
    if (std.mem.eql(u8, e, ".md")) return .md;
    if (std.mem.eql(u8, e, ".html") or std.mem.eql(u8, e, ".htm")) return .html;
    if (std.mem.eql(u8, e, ".tex")) return .tex;
    return null;
}

fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    return try f.readToEndAlloc(alloc, 1 << 26);
}

fn writeFile(path: []const u8, data: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    _ = try f.writeAll(data);
}

pub fn run(alloc: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const in_path = it.next() orelse {
        try std.io.getStdErr().writer().writeAll(
            "Usage: docz convert <input.{dcz|md|html|htm|tex}> [--to|-t <output.{dcz|md|html|tex}>]\n",
        );
        return error.Invalid;
    };

    // parse flags: --to / -t
    var out_path: ?[]const u8 = null;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--to") or std.mem.eql(u8, arg, "-t")) {
            out_path = it.next() orelse {
                try std.io.getStdErr().writer().writeAll("convert: --to requires a value\n");
                return error.Invalid;
            };
        } else {
            try std.io.getStdErr().writer().print("convert: unknown arg: {s}\n", .{arg});
            return error.Invalid;
        }
    }

    const in_kind = detectKindFromPath(in_path) orelse {
        try std.io.getStdErr().writer().print("convert: unsupported input type: {s}\n", .{in_path});
        return error.Invalid;
    };

    const input = try readFileAlloc(alloc, in_path);
    defer alloc.free(input);

    var out_buf: []u8 = &[_]u8{}; // will be reassigned
    defer if (out_buf.len != 0 and out_buf.ptr != input.ptr) alloc.free(out_buf);

    if (in_kind == .dcz) {
        // Parse DCZ → AST once
        const tokens = try docz.Tokenizer.tokenize(input, alloc);
        defer {
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
            .html => out_buf = try html_export.exportAstToHtml(&ast, alloc),
            .tex => out_buf = try latex_export.exportAstToLatex(&ast, alloc),
            .dcz => unreachable, // handled above
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
            try std.io.getStdErr().writer().print("convert: unsupported output type: {s}\n", .{p});
            return error.Invalid;
        }
        try writeFile(p, out_buf);
    } else {
        try std.io.getStdOut().writer().writeAll(out_buf);
    }
}
