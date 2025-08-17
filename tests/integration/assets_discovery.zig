const std = @import("std");
const testing = std.testing;

const assets = @import("../../src/cli/assets.zig");

fn expectContains(hay: []const u8, needle: []const u8) !void {
    try testing.expect(std.mem.indexOf(u8, hay, needle) != null);
}

test "assets.findTailwindCss prefers monorepo theme over vendored" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Remember current CWD and switch to temp
    const old_cwd = try std.fs.cwd().realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(old_cwd);
    defer std.os.chdir(old_cwd) catch {};
    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);
    try std.os.chdir(tmp_path);

    // Create BOTH monorepo and vendored theme paths.
    try tmp.dir.makePath("themes/default/dist");
    try tmp.dir.makePath("third_party/tailwind/docz-theme-4.1.11/css");
    try tmp.dir.makePath("third_party/tailwind/docz-theme-4.1.12/css");

    // Write the files
    {
        var f = try tmp.dir.createFile("themes/default/dist/docz.tailwind.css", .{ .truncate = true });
        defer f.close();
        try f.writeAll("/* mono */");
    }
    {
        var f = try tmp.dir.createFile("third_party/tailwind/docz-theme-4.1.11/css/docz.tailwind.css", .{ .truncate = true });
        defer f.close();
        try f.writeAll("/* v411 */");
    }
    {
        var f = try tmp.dir.createFile("third_party/tailwind/docz-theme-4.1.12/css/docz.tailwind.css", .{ .truncate = true });
        defer f.close();
        try f.writeAll("/* v412 */");
    }

    const path_opt = try assets.findTailwindCss(testing.allocator);
    defer if (path_opt) |p| testing.allocator.free(p);

    try testing.expect(path_opt != null);
    const p = path_opt.?;
    try testing.expectEqualStrings("themes/default/dist/docz.tailwind.css", p);
}

test "assets.findTailwindCss picks newest vendored by mtime with lexicographic tie-break" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Switch cwd -> tmp
    const old_cwd = try std.fs.cwd().realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(old_cwd);
    defer std.os.chdir(old_cwd) catch {};
    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);
    try std.os.chdir(tmp_path);

    // Only vendored; two versions
    try tmp.dir.makePath("third_party/tailwind/docz-theme-4.1.11/css");
    try tmp.dir.makePath("third_party/tailwind/docz-theme-4.1.12/css");

    {
        var f = try tmp.dir.createFile("third_party/tailwind/docz-theme-4.1.11/css/docz.tailwind.css", .{ .truncate = true });
        defer f.close();
        try f.writeAll("/* 4.1.11 */");
    }
    {
        var f = try tmp.dir.createFile("third_party/tailwind/docz-theme-4.1.12/css/docz.tailwind.css", .{ .truncate = true });
        defer f.close();
        try f.writeAll("/* 4.1.12 */");
    }

    const got = try assets.findTailwindCss(testing.allocator);
    defer if (got) |p| testing.allocator.free(p);

    try testing.expect(got != null);
    try expectContains(got.?, "docz-theme-4.1.12");
}

test "assets.findKatexAssets returns hrefs rooted at /third_party/katex/<ver>/dist/..." {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Switch cwd -> tmp
    const old_cwd = try std.fs.cwd().realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(old_cwd);
    defer std.os.chdir(old_cwd) catch {};
    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);
    try std.os.chdir(tmp_path);

    // Create two versions (older + newer)
    try tmp.dir.makePath("third_party/katex/0.16.21/dist/contrib");
    try tmp.dir.makePath("third_party/katex/0.16.22/dist/contrib");

    {
        var f = try tmp.dir.createFile("third_party/katex/0.16.21/dist/katex.min.css", .{ .truncate = true });
        defer f.close();
        try f.writeAll("/* css */");
        var g = try tmp.dir.createFile("third_party/katex/0.16.21/dist/katex.min.js", .{ .truncate = true });
        defer g.close();
        var h = try tmp.dir.createFile("third_party/katex/0.16.21/dist/contrib/auto-render.min.js", .{ .truncate = true });
        defer h.close();
    }
    {
        var f = try tmp.dir.createFile("third_party/katex/0.16.22/dist/katex.min.css", .{ .truncate = true });
        defer f.close();
        try f.writeAll("/* css */");
        var g = try tmp.dir.createFile("third_party/katex/0.16.22/dist/katex.min.js", .{ .truncate = true });
        defer g.close();
        var h = try tmp.dir.createFile("third_party/katex/0.16.22/dist/contrib/auto-render.min.js", .{ .truncate = true });
        defer h.close();
    }

    const k = try assets.findKatexAssets(testing.allocator);
    defer if (k) |kk| {
        testing.allocator.free(kk.css_href);
        testing.allocator.free(kk.js_href);
        testing.allocator.free(kk.auto_href);
    };

    try testing.expect(k != null);
    try expectContains(k.?.css_href, "/third_party/katex/0.16.22/dist/katex.min.css");
    try expectContains(k.?.js_href, "/third_party/katex/0.16.22/dist/katex.min.js");
    try expectContains(k.?.auto_href, "/third_party/katex/0.16.22/dist/contrib/auto-render.min.js");
}

test "assets.copyFileStreaming copies bytes verbatim" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Write a source file
    {
        var f = try tmp.dir.createFile("src.txt", .{ .truncate = true });
        defer f.close();
        try f.writeAll("hello world");
    }

    // Perform copy using absolute paths (resolve both)
    const base = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(base);

    const src = try std.fs.path.join(testing.allocator, &.{ base, "src.txt" });
    defer testing.allocator.free(src);
    const dest = try std.fs.path.join(testing.allocator, &.{ base, "nested", "out.txt" });
    defer testing.allocator.free(dest);

    try assets.copyFileStreaming(src, dest);

    // Read back
    var f2 = try tmp.dir.openFile("nested/out.txt", .{});
    defer f2.close();
    const buf = try f2.readToEndAlloc(testing.allocator, 1 << 20);
    defer testing.allocator.free(buf);

    try testing.expectEqualStrings("hello world", buf);
}

test "assets.fileMTime returns a positive number" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        var f = try tmp.dir.createFile("a.txt", .{ .truncate = true });
        defer f.close();
        try f.writeAll("x");
    }

    const base = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(base);
    const abs = try std.fs.path.join(testing.allocator, &.{ base, "a.txt" });
    defer testing.allocator.free(abs);

    const mt = try assets.fileMTime(abs);
    try testing.expect(mt > 0);
}
