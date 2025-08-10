const std = @import("std");

pub const Kind = enum { dcz, md, html, tex };

// ---------- stderr helper ----------
fn errW() std.fs.File.Writer {
    var f = std.fs.File{ .handle = std.io.getStdErrHandle() };
    return f.writer();
}

pub fn detectKindFromPath(p: []const u8) ?Kind {
    const ext = std.fs.path.extension(p);
    if (ext.len == 0) return null;
    if (std.ascii.eqlIgnoreCase(ext, ".dcz")) return .dcz;
    if (std.ascii.eqlIgnoreCase(ext, ".md")) return .md;
    if (std.ascii.eqlIgnoreCase(ext, ".html") or std.ascii.eqlIgnoreCase(ext, ".htm")) return .html;
    if (std.ascii.eqlIgnoreCase(ext, ".tex")) return .tex;
    return null;
}

pub fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    return try f.readToEndAlloc(alloc, 1 << 26);
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    const cwd = std.fs.cwd();
    if (std.fs.path.dirname(path)) |dirpart| {
        try cwd.makePath(dirpart);
    }
    var f = try cwd.createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}

pub fn parseTo(it: *std.process.ArgIterator) !?[]const u8 {
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--to") or std.mem.eql(u8, arg, "-t")) {
            return it.next() orelse {
                try errW().writeAll("--to requires a value\n");
                return error.Invalid;
            };
        } else {
            try errW().print("unknown arg: {s}\n", .{arg});
            return error.Invalid;
        }
    }
    return null;
}

test "common.detectKindFromPath: case-insensitive mapping" {
    try std.testing.expect(detectKindFromPath("x.dcz") == .dcz);
    try std.testing.expect(detectKindFromPath("x.DCZ") == .dcz);

    try std.testing.expect(detectKindFromPath("x.md") == .md);
    try std.testing.expect(detectKindFromPath("x.MD") == .md);

    try std.testing.expect(detectKindFromPath("x.html") == .html);
    try std.testing.expect(detectKindFromPath("x.htm") == .html);
    try std.testing.expect(detectKindFromPath("x.HTML") == .html);
    try std.testing.expect(detectKindFromPath("x.HTM") == .html);

    try std.testing.expect(detectKindFromPath("x.tex") == .tex);
    try std.testing.expect(detectKindFromPath("x.TEX") == .tex);

    try std.testing.expect(detectKindFromPath("x") == null);
    try std.testing.expect(detectKindFromPath("x.unknown") == null);
}
