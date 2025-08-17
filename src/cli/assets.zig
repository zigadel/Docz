const std = @import("std");

// Prefer monorepo-built theme if present,
// otherwise choose newest vendored theme by mtime (tie-break lexicographically).
pub fn findTailwindCss(alloc: std.mem.Allocator) !?[]u8 {
    // 1) Monorepo theme (takes priority)
    const mono_css = "themes/default/dist/docz.tailwind.css";
    const mono_ok = blk1: {
        std.fs.cwd().access(mono_css, .{}) catch break :blk1 false;
        break :blk1 true;
    };
    if (mono_ok) return try alloc.dupe(u8, mono_css);

    // 2) Vendored: third_party/tailwind/docz-theme-*/css/docz.tailwind.css
    const root = "third_party/tailwind";
    var dir = std.fs.cwd().openDir(root, .{ .iterate = true }) catch |e| {
        if (e == error.FileNotFound) return null;
        return e;
    };
    defer dir.close();

    var it = dir.iterate();

    var best_path: ?[]u8 = null;
    var best_name: ?[]u8 = null;
    var best_mtime: i128 = 0;

    while (try it.next()) |ent| {
        if (ent.kind != .directory) continue;
        if (!std.mem.startsWith(u8, ent.name, "docz-theme-")) continue;

        const css_abs = try std.fs.path.join(alloc, &.{ root, ent.name, "css", "docz.tailwind.css" });
        const present = blk2: {
            std.fs.cwd().access(css_abs, .{}) catch break :blk2 false;
            break :blk2 true;
        };
        if (!present) {
            alloc.free(css_abs);
            continue;
        }

        const st = std.fs.cwd().statFile(css_abs) catch {
            // fall back to lexicographic name if stat fails
            const better = if (best_name) |bn| std.mem.lessThan(u8, bn, ent.name) else true;
            if (better) {
                if (best_path) |bp| alloc.free(bp);
                if (best_name) |bn| alloc.free(bn);
                best_path = css_abs;
                best_name = try alloc.dupe(u8, ent.name);
            } else {
                alloc.free(css_abs);
            }
            continue;
        };

        const better = if (best_path == null)
            true
        else
            (st.mtime > best_mtime) or
                (st.mtime == best_mtime and if (best_name) |bn| std.mem.lessThan(u8, bn, ent.name) else true);

        if (better) {
            if (best_path) |bp| alloc.free(bp);
            if (best_name) |bn| alloc.free(bn);
            best_path = css_abs;
            best_name = try alloc.dupe(u8, ent.name);
            best_mtime = st.mtime;
        } else {
            alloc.free(css_abs);
        }
    }

    if (best_name) |bn| alloc.free(bn);
    return best_path;
}

// Discover newest KaTeX under third_party/katex/*/dist and
// return *hrefs* that the preview server can serve (prefix: /third_party/...).
pub fn findKatexAssets(alloc: std.mem.Allocator) !?struct {
    css_href: []u8,
    js_href: []u8,
    auto_href: []u8,
} {
    const root = "third_party/katex";
    var dir = std.fs.cwd().openDir(root, .{ .iterate = true }) catch |e| {
        if (e == error.FileNotFound) return null;
        return e;
    };
    defer dir.close();

    var it = dir.iterate();

    var best_ver: ?[]u8 = null;
    var best_mtime: i128 = 0;

    while (try it.next()) |ent| {
        if (ent.kind != .directory) continue;
        if (ent.name.len == 0 or ent.name[0] == '.') continue;

        const css_disk = try std.fs.path.join(alloc, &.{ root, ent.name, "dist", "katex.min.css" });
        const present = blk: {
            std.fs.cwd().access(css_disk, .{}) catch break :blk false;
            break :blk true;
        };
        if (!present) {
            alloc.free(css_disk);
            continue;
        }

        const st = std.fs.cwd().statFile(css_disk) catch {
            alloc.free(css_disk);
            // lexicographic fallback
            const better = if (best_ver) |bv| std.mem.lessThan(u8, bv, ent.name) else true;
            if (better) {
                if (best_ver) |bv| alloc.free(bv);
                best_ver = try alloc.dupe(u8, ent.name);
            }
            continue;
        };
        alloc.free(css_disk);

        const better_time = (best_ver == null) or (st.mtime > best_mtime) or
            (st.mtime == best_mtime and if (best_ver) |bv| std.mem.lessThan(u8, bv, ent.name) else true);

        if (better_time) {
            if (best_ver) |bv| alloc.free(bv);
            best_ver = try alloc.dupe(u8, ent.name);
            best_mtime = st.mtime;
        }
    }

    if (best_ver == null) return null;
    defer alloc.free(best_ver.?);

    const css_href = try std.fmt.allocPrint(alloc, "/third_party/katex/{s}/dist/katex.min.css", .{best_ver.?});
    const js_href = try std.fmt.allocPrint(alloc, "/third_party/katex/{s}/dist/katex.min.js", .{best_ver.?});
    const auto_href = try std.fmt.allocPrint(alloc, "/third_party/katex/{s}/dist/contrib/auto-render.min.js", .{best_ver.?});

    return .{ .css_href = css_href, .js_href = js_href, .auto_href = auto_href };
}

// ─────────────────────────────────────────────────────────────
// Tiny file helpers (used by run.zig)
// ─────────────────────────────────────────────────────────────

pub fn copyFileStreaming(src_abs: []const u8, dest_abs: []const u8) !void {
    if (std.fs.path.dirname(dest_abs)) |d| try std.fs.cwd().makePath(d);

    var in_file = try std.fs.cwd().openFile(src_abs, .{});
    defer in_file.close();

    var out_file = try std.fs.cwd().createFile(dest_abs, .{ .truncate = true });
    defer out_file.close();

    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try in_file.read(&buf);
        if (n == 0) break;
        try out_file.writeAll(buf[0..n]);
    }
}

pub fn fileMTime(path: []const u8) !i128 {
    const st = try std.fs.cwd().statFile(path);
    return st.mtime;
}
