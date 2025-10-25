const std = @import("std");

/// Cross-project filesystem + path helpers.
/// Import styles supported:
///   const Fs = @import("util_fs").Fs;                  // namespace
///   const fileExists = @import("util_fs").fileExists;  // single symbol
pub const Fs = struct {
    /// CWD-relative or absolute. Returns false on any error.
    pub fn exists(path: []const u8) bool {
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Read whole file into allocator (cap guards giant files).
    pub fn readAllAlloc(a: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
        return std.fs.cwd().readFileAlloc(path, a, max_bytes);
    }

    /// Write full text file (creates parent dirs as needed).
    pub fn writeAll(path: []const u8, body: []const u8) !void {
        if (std.fs.path.dirname(path)) |d| try std.fs.cwd().makePath(d);
        var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer f.close();
        try f.writeAll(body);
    }

    /// Copy (creates parent dirs as needed).
    pub fn copy(src_abs: []const u8, dest_abs: []const u8) !void {
        if (std.fs.path.dirname(dest_abs)) |d| try std.fs.cwd().makePath(d);

        var in_f = try std.fs.cwd().openFile(src_abs, .{});
        defer in_f.close();

        var out_f = try std.fs.cwd().createFile(dest_abs, .{ .truncate = true });
        defer out_f.close();

        var buf: [64 * 1024]u8 = undefined;
        while (true) {
            const n = try in_f.read(&buf);
            if (n == 0) break;
            try out_f.writeAll(buf[0..n]);
        }
    }

    /// Simple 2-segment URLish join. Kept for backwards compat with older code.
    /// (Uses '/' and does NOT trim leading slash on `b_path`.)
    pub fn join2(a: std.mem.Allocator, a_path: []const u8, b_path: []const u8) ![]const u8 {
        if (a_path.len == 0) return a.dupe(u8, b_path);
        if (b_path.len == 0) return a.dupe(u8, a_path);
        if (a_path[a_path.len - 1] == '/')
            return std.fmt.allocPrint(a, "{s}{s}", .{ a_path, b_path });
        return std.fmt.allocPrint(a, "{s}/{s}", .{ a_path, b_path });
    }

    /// Filesystem join using platform-correct separator.
    pub fn join2Fs(a: std.mem.Allocator, left: []const u8, right: []const u8) ![]u8 {
        if (left.len == 0) return a.dupe(u8, right);
        if (right.len == 0) return a.dupe(u8, left);
        return std.fs.path.join(a, &.{ left, right });
    }

    /// URL/path join using '/', trimming any leading '/' from right to avoid '//'.
    pub fn join2Url(a: std.mem.Allocator, left: []const u8, right: []const u8) ![]u8 {
        if (left.len == 0) return a.dupe(u8, right);
        if (right.len == 0) return a.dupe(u8, left);

        var r = right;
        while (r.len > 0 and r[0] == '/') r = r[1..];

        if (left[left.len - 1] == '/')
            return std.fmt.allocPrint(a, "{s}{s}", .{ left, r });
        return std.fmt.allocPrint(a, "{s}/{s}", .{ left, r });
    }
};

// DRY, top-level aliases so callers can import exactly what they need.
pub const fileExists = Fs.exists;
pub const readFileAlloc = Fs.readAllAlloc;
pub const writeTextFile = Fs.writeAll;
pub const copyFile = Fs.copy;
pub const join2Fs = Fs.join2Fs;
pub const join2Url = Fs.join2Url;

// ───────────────────────────
// Unit tests
// ───────────────────────────

test "exists + writeAll + readAllAlloc round-trip" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const alloc = std.testing.allocator;

    const base = (try tmp.dir.realpathAlloc(alloc, ".")).?;
    defer alloc.free(base);

    const fpath = try std.fs.path.join(alloc, &.{ base, "nested", "file.txt" });
    defer alloc.free(fpath);

    try Fs.writeAll(fpath, "hello");
    try std.testing.expect(Fs.exists(fpath));

    const got = try Fs.readAllAlloc(alloc, fpath, 1 << 20);
    defer alloc.free(got);
    try std.testing.expectEqualStrings("hello", got);
}

test "copy creates parents and duplicates bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const alloc = std.testing.allocator;
    const base = (try tmp.dir.realpathAlloc(alloc, ".")).?;
    defer alloc.free(base);

    const src = try std.fs.path.join(alloc, &.{ base, "src.txt" });
    defer alloc.free(src);
    const dst = try std.fs.path.join(alloc, &.{ base, "deep", "dir", "dst.txt" });
    defer alloc.free(dst);

    try Fs.writeAll(src, "abc123");
    try Fs.copy(src, dst);

    try std.testing.expect(Fs.exists(dst));
    const got = try Fs.readAllAlloc(alloc, dst, 1 << 20);
    defer alloc.free(got);
    try std.testing.expectEqualStrings("abc123", got);
}

test "join2Fs uses platform separator and handles empties" {
    const alloc = std.testing.allocator;
    const sep = std.fs.path.sep;

    const a = try Fs.join2Fs(alloc, "x", "y");
    defer alloc.free(a);
    const expect = try std.fmt.allocPrint(alloc, "x{c}y", .{sep});
    defer alloc.free(expect);
    try std.testing.expectEqualStrings(expect, a);

    const b = try Fs.join2Fs(alloc, "", "y");
    defer alloc.free(b);
    try std.testing.expectEqualStrings("y", b);

    const c = try Fs.join2Fs(alloc, "x", "");
    defer alloc.free(c);
    try std.testing.expectEqualStrings("x", c);
}

test "join2Url normalizes boundary slashes" {
    const alloc = std.testing.allocator;

    const a = try Fs.join2Url(alloc, "a", "b");
    defer alloc.free(a);
    try std.testing.expectEqualStrings("a/b", a);

    const b = try Fs.join2Url(alloc, "a/", "b");
    defer alloc.free(b);
    try std.testing.expectEqualStrings("a/b", b);

    const c = try Fs.join2Url(alloc, "a", "/b");
    defer alloc.free(c);
    try std.testing.expectEqualStrings("a/b", c);

    const d = try Fs.join2Url(alloc, "/a/", "/b");
    defer alloc.free(d);
    try std.testing.expectEqualStrings("/a/b", d);

    const e = try Fs.join2Url(alloc, "", "x");
    defer alloc.free(e);
    try std.testing.expectEqualStrings("x", e);

    const f = try Fs.join2Url(alloc, "x", "");
    defer alloc.free(f);
    try std.testing.expectEqualStrings("x", f);
}

test "legacy join2 behaves like simple URL join" {
    const alloc = std.testing.allocator;

    const x = try Fs.join2(alloc, "a", "b");
    defer alloc.free(x);
    try std.testing.expectEqualStrings("a/b", x);

    const y = try Fs.join2(alloc, "a/", "b");
    defer alloc.free(y);
    try std.testing.expectEqualStrings("a/b", y);

    const z = try Fs.join2(alloc, "", "b");
    defer alloc.free(z);
    try std.testing.expectEqualStrings("b", z);
}
