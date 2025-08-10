const std = @import("std");

pub const Kind = enum { dcz, md, html, tex };

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
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    _ = try f.writeAll(data);
}

pub fn parseTo(it: *std.process.ArgIterator) !?[]const u8 {
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--to") or std.mem.eql(u8, arg, "-t")) {
            return it.next() orelse {
                try std.io.getStdErr().writer().writeAll("--to requires a value\n");
                return error.Invalid;
            };
        } else {
            try std.io.getStdErr().writer().print("unknown arg: {s}\n", .{arg});
            return error.Invalid;
        }
    }
    return null;
}
