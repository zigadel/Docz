const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var it = try std.process.argsWithAllocator(A);
    defer it.deinit();
    _ = it.next(); // program name

    const cmd = it.next() orelse return usage();

    if (std.mem.eql(u8, cmd, "fetch")) {
        const what = it.next() orelse return usage();
        if (std.mem.eql(u8, what, "katex")) return try sub_fetch_katex(A, &it);
        if (std.mem.eql(u8, what, "tailwind-theme")) return try sub_fetch_tailwind_theme(A, &it);
        return usage();
    }
    if (std.mem.eql(u8, cmd, "checksums")) return try writeAllChecksums(A);
    if (std.mem.eql(u8, cmd, "verify")) return try verifyAll(A);
    if (std.mem.eql(u8, cmd, "freeze")) return try freezeLock(A);
    if (std.mem.eql(u8, cmd, "bootstrap")) return try sub_bootstrap(A, &it);

    return usage();
}

const USAGE: []const u8 =
    \\Usage:
    \\  zig run tools/vendor.zig -- fetch katex <version> [--manifest <path>] [--cdn jsdelivr|unpkg]
    \\  zig run tools/vendor.zig -- fetch tailwind-theme <version> <url-or-path>
    \\  zig run tools/vendor.zig -- checksums
    \\  zig run tools/vendor.zig -- verify
    \\  zig run tools/vendor.zig -- freeze
    \\  zig run tools/vendor.zig -- bootstrap [--config tools/vendor.config]
    \\
    \\Notes:
    \\- No versions are hardcoded. We scan third_party/** dynamically.
    \\- KaTeX fetch uses a manifest you provide (one relative path per line from package root).
    \\- checksums/verify operate on any version folders that contain files.
    \\
;

fn usage() !void {
    std.debug.print("{s}", .{USAGE});
    return error.Invalid;
}

// ─────────────────────────────────────────────────────────────
// tiny IO helpers
// ─────────────────────────────────────────────────────────────

fn slurpFile(a: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    var out = std.ArrayList(u8){};
    defer out.deinit(a);

    var tmp: [32 * 1024]u8 = undefined;
    var total: usize = 0;
    while (true) {
        const n = try f.read(&tmp);
        if (n == 0) break;
        total += n;
        if (total > max) return error.FileTooLarge;
        try out.appendSlice(a, tmp[0..n]);
    }
    return try out.toOwnedSlice(a);
}

fn httpGetToFile(a: std.mem.Allocator, url: []const u8, dest_abs: []const u8) !void {
    if (std.fs.path.dirname(dest_abs)) |d| try std.fs.cwd().makePath(d);

    var client = std.http.Client{ .allocator = a };
    defer client.deinit();

    var current_url = try a.dupe(u8, url);
    defer a.free(current_url);

    var redirects_left: u8 = 5;

    while (true) {
        const current = try std.Uri.parse(current_url);        var req = try client.request(.GET, current, .{});
        defer req.deinit();try req.wait();

        const code: u16 = @intFromEnum(req.response.status);
        const klass: u16 = code / 100;

        if (klass == 2) {
            var out_file = try std.fs.cwd().createFile(dest_abs, .{ .truncate = true });
            defer out_file.close();

            var buf: [32 * 1024]u8 = undefined;
            while (true) {
                const n = try req.reader().read(&buf);
                if (n == 0) break;
                try out_file.writeAll(buf[0..n]);
            }
            break;
        } else if (klass == 3) {
            if (redirects_left == 0) return error.HttpFailed;
            redirects_left -%= 1;

            const loc = req.response.location orelse blk: {
                var it = req.response.iterateHeaders();
                while (it.next()) |h| {
                    if (std.ascii.eqlIgnoreCase(h.name, "location")) break :blk h.value;
                }
                break :blk null;
            } orelse return error.HttpFailed;

            const next_url = try resolveRedirectAgainst(a, current_url, loc);
            a.free(current_url);
            current_url = next_url;
            continue;
        } else {
            std.debug.print("HTTP {d} for {s}\n", .{ code, current_url });
            return error.HttpFailed;
        }
    }
}

// ---------- helpers for redirect resolution (string-based) ----------

fn originEndIndex(u: []const u8) usize {
    if (std.mem.indexOf(u8, u, "://")) |i| {
        const after_scheme = i + 3;
        if (std.mem.indexOfScalarPos(u8, u, after_scheme, '/')) |j|
            return j;
        return u.len; // no path → whole string is origin
    }
    return 0;
}

fn resolveRedirectAgainst(a: std.mem.Allocator, base_url: []const u8, loc: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, loc, "://") != null)
        return a.dupe(u8, loc);

    const origin_end = originEndIndex(base_url);
    if (origin_end == 0) return error.BadBaseUrl;

    if (loc.len > 0 and loc[0] == '/') {
        const origin = base_url[0..origin_end];
        return std.fmt.allocPrint(a, "{s}{s}", .{ origin, loc });
    }

    var dir_end = origin_end;
    if (origin_end < base_url.len) {
        const path = base_url[origin_end..];
        if (std.mem.lastIndexOfScalar(u8, path, '/')) |ls| {
            dir_end = origin_end + ls + 1;
        } else {
            dir_end = origin_end;
        }
    }
    const before = base_url[0..dir_end];
    return std.fmt.allocPrint(a, "{s}{s}", .{ before, loc });
}

fn copyFile(src_abs: []const u8, dest_abs: []const u8) !void {
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

fn writeTextFile(dest_abs: []const u8, body: []const u8) !void {
    if (std.fs.path.dirname(dest_abs)) |d| try std.fs.cwd().makePath(d);
    var f = try std.fs.cwd().createFile(dest_abs, .{ .truncate = true });
    defer f.close();
    try f.writeAll(body);
}

fn fileExists(abs: []const u8) bool {
    _ = std.fs.cwd().access(abs, .{}) catch return false;
    return true;
}

// ─────────────────────────────────────────────────────────────
// KaTeX fetch
// ─────────────────────────────────────────────────────────────

fn fetchKatex(a: std.mem.Allocator, ver: []const u8, manifest: []const u8, cdn: []const u8) !void {
    const base = try std.fmt.allocPrint(a, "third_party/katex/{s}", .{ver});
    defer a.free(base);

    var mf = std.fs.cwd().openFile(manifest, .{}) catch |e| {
        std.debug.print("katex: manifest not found: {s} ({s})\n", .{ manifest, @errorName(e) });
        return e;
    };
    defer mf.close();

    var mb = std.ArrayList(u8){};
    defer mb.deinit(a);
    var tmp: [8 * 1024]u8 = undefined;
    while (true) {
        const n = try mf.read(&tmp);
        if (n == 0) break;
        try mb.appendSlice(a, tmp[0..n]);
    }
    const mb_slice = mb.items;

    var ok: usize = 0;
    var itl = std.mem.splitScalar(u8, mb_slice, '\n');
    while (itl.next()) |raw| {
        const rel = std.mem.trim(u8, raw, " \t\r");
        if (rel.len == 0 or rel[0] == '#') continue;

        const url = switch (cdn[0]) {
            'j' => try std.fmt.allocPrint(a, "https://cdn.jsdelivr.net/npm/katex@{s}/{s}", .{ ver, rel }),
            'u' => try std.fmt.allocPrint(a, "https://unpkg.com/katex@{s}/{s}", .{ ver, rel }),
            else => try std.fmt.allocPrint(a, "https://cdn.jsdelivr.net/npm/katex@{s}/{s}", .{ ver, rel }),
        };
        defer a.free(url);

        const dest = try std.fs.path.join(a, &.{ base, rel });
        defer a.free(dest);

        try httpGetToFile(a, url, dest);
        ok += 1;
    }

    const vfile = try std.fs.path.join(a, &.{ base, "VERSION" });
    defer a.free(vfile);
    try writeTextFile(vfile, ver);

    std.debug.print("katex: fetched {d} files into {s}\n", .{ ok, base });
}

fn sub_fetch_katex(a: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const ver = it.next() orelse {
        std.debug.print("fetch katex: missing <version>, e.g. 0.16.11\n", .{});
        return error.Invalid;
    };

    var manifest_path: ?[]const u8 = null;
    var cdn: []const u8 = "jsdelivr";
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--manifest")) {
            manifest_path = it.next() orelse {
                std.debug.print("fetch katex: --manifest <path> required\n", .{});
                return error.Invalid;
            };
        } else if (std.mem.eql(u8, arg, "--cdn")) {
            cdn = it.next() orelse {
                std.debug.print("fetch katex: --cdn jsdelivr|unpkg\n", .{});
                return error.Invalid;
            };
        } else {
            std.debug.print("fetch katex: unknown option {s}\n", .{arg});
            return error.Invalid;
        }
    }
    const manifest = manifest_path orelse {
        std.debug.print("fetch katex: --manifest <path> is required (no file list is hardcoded)\n", .{});
        return error.Invalid;
    };

    try fetchKatex(a, ver, manifest, cdn);
}

// ─────────────────────────────────────────────────────────────
// Tailwind theme fetch
// ─────────────────────────────────────────────────────────────

fn fetchTailwindTheme(a: std.mem.Allocator, ver: []const u8, src: []const u8) !void {
    const base = try std.fmt.allocPrint(a, "third_party/tailwind/docz-theme-{s}", .{ver});
    defer a.free(base);

    const dest = try std.fs.path.join(a, &.{ base, "css", "docz.tailwind.css" });
    defer a.free(dest);

    if (std.mem.startsWith(u8, src, "http://") or std.mem.startsWith(u8, src, "https://")) {
        try httpGetToFile(a, src, dest);
    } else {
        try copyFile(src, dest);
    }

    const vfile = try std.fs.path.join(a, &.{ base, "VERSION" });
    defer a.free(vfile);
    try writeTextFile(vfile, ver);

    std.debug.print("tailwind: placed theme {s} -> {s}\n", .{ src, dest });
}

fn sub_fetch_tailwind_theme(a: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const ver = it.next() orelse {
        std.debug.print("fetch tailwind-theme: missing <version>, e.g. 1.0.0\n", .{});
        return error.Invalid;
    };
    const src = it.next() orelse {
        std.debug.print("fetch tailwind-theme: missing <url-or-path>\n", .{});
        return error.Invalid;
    };

    try fetchTailwindTheme(a, ver, src);
}

// ─────────────────────────────────────────────────────────────
// Checksums / Verify (dynamic discovery)
// ─────────────────────────────────────────────────────────────

const IGNORE_BASENAMES = [_][]const u8{
    "CHECKSUMS.sha256",
    "VERSION",
    ".DS_Store",
    "Thumbs.db",
};

fn isIgnoredBase(b: []const u8) bool {
    for (IGNORE_BASENAMES) |name| if (std.mem.eql(u8, b, name)) return true;
    return false;
}

fn walkFilesCollect(a: std.mem.Allocator, root_abs: []const u8, out: *std.ArrayList([]const u8)) !void {
    var dir = try std.fs.cwd().openDir(root_abs, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |e| {
        const name = e.name;
        if (name.len == 0 or name[0] == '.') continue;

        const abs = try std.fs.path.join(a, &.{ root_abs, name });
        switch (e.kind) {
            .file => {
                if (!isIgnoredBase(name)) try out.append(a, abs) else a.free(abs);
            },
            .directory => {
                try walkFilesCollect(a, abs, out);
                a.free(abs);
            },
            else => a.free(abs),
        }
    }
}

fn sha256HexOfFile(a: std.mem.Allocator, abs: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(abs, .{});
    defer f.close();
    const st = try f.stat();
    const buf = try a.alloc(u8, @intCast(st.size));
    defer a.free(buf);
    _ = try f.readAll(buf);

    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(buf);

    var digest: [32]u8 = undefined;
    h.final(&digest);

    return try bytesToHexLower(a, &digest);
}

fn writeChecksumsFor(a: std.mem.Allocator, base_abs: []const u8) !void {
    var files = std.ArrayList([]const u8){};
    defer {
        for (files.items) |p| a.free(p);
        files.deinit(a);
    }
    try walkFilesCollect(a, base_abs, &files);
    if (files.items.len == 0) return;

    const outp = try std.fs.path.join(a, &.{ base_abs, "CHECKSUMS.sha256" });
    defer a.free(outp);
    var f = try std.fs.cwd().createFile(outp, .{ .truncate = true });
    defer f.close();

    const root_len = base_abs.len;
    for (files.items) |abs| {
        const hex = try sha256HexOfFile(a, abs);
        defer a.free(hex);

        var rel: []const u8 = abs;
        if (abs.len > root_len + 1 and
            std.mem.eql(u8, abs[0..root_len], base_abs) and
            abs[root_len] == std.fs.path.sep)
        {
            rel = abs[root_len + 1 ..];
        }

        const line = try std.fmt.allocPrint(a, "{s}  {s}\n", .{ hex, rel });
        defer a.free(line);
        try f.writeAll(line);
    }
}

fn verifyOne(a: std.mem.Allocator, base_abs: []const u8) !void {
    const cpath = try std.fs.path.join(a, &.{ base_abs, "CHECKSUMS.sha256" });
    defer a.free(cpath);

    if (!fileExists(cpath)) {
        std.debug.print("verify: skipped (no CHECKSUMS) {s}\n", .{base_abs});
        return;
    }

    const buf = try slurpFile(a, cpath, 1 << 22);
    defer a.free(buf);

    var ok: usize = 0;
    var tot: usize = 0;

    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |ln_raw| {
        const ln = std.mem.trim(u8, ln_raw, " \t\r");
        if (ln.len == 0) continue;
        if (ln.len < 66) return error.BadChecksumLine;

        const hex = ln[0..64];
        var sp = ln[64..];
        while (sp.len > 0 and (sp[0] == ' ' or sp[0] == '\t')) sp = sp[1..];
        const rel = sp;

        const abs = try std.fs.path.join(a, &.{ base_abs, rel });
        defer a.free(abs);
        if (!fileExists(abs)) {
            std.debug.print("missing: {s}\n", .{abs});
            return error.FileMissing;
        }

        const got = try sha256HexOfFile(a, abs);
        defer a.free(got);

        tot += 1;
        if (!std.mem.eql(u8, hex, got)) {
            std.debug.print("mismatch: {s}\n", .{abs});
            return error.ChecksumMismatch;
        }
        ok += 1;
    }
    std.debug.print("verify: {d}/{d} ok under {s}\n", .{ ok, tot, base_abs });
}

fn discoverVersionRoots(a: std.mem.Allocator) !std.ArrayList([]const u8) {
    var out = std.ArrayList([]const u8){};

    const tp = "third_party";
    var tp_dir = std.fs.cwd().openDir(tp, .{ .iterate = true }) catch |e| {
        if (e != error.FileNotFound) return e;
        return out; // nothing to discover
    };
    defer tp_dir.close();

    var it1 = tp_dir.iterate();
    while (try it1.next()) |family| {
        if (family.kind != .directory) continue;
        if (family.name.len == 0 or family.name[0] == '.') continue;

        const fam_abs = try std.fs.path.join(a, &.{ tp, family.name });
        defer a.free(fam_abs);

        var fam_dir = try std.fs.cwd().openDir(fam_abs, .{ .iterate = true });
        defer fam_dir.close();

        var it2 = fam_dir.iterate();
        while (try it2.next()) |ver| {
            if (ver.kind != .directory) continue;
            if (ver.name.len == 0 or ver.name[0] == '.') continue;

            const root_abs = try std.fs.path.join(a, &.{ fam_abs, ver.name });

            var files = std.ArrayList([]const u8){};
            defer {
                for (files.items) |p| a.free(p);
                files.deinit(a);
            }
            try walkFilesCollect(a, root_abs, &files);
            if (files.items.len > 0) {
                try out.append(a, try a.dupe(u8, root_abs));
            }
            a.free(root_abs);
        }
    }

    return out;
}

pub fn writeAllChecksums(a: std.mem.Allocator) !void {
    var roots = try discoverVersionRoots(a);
    defer {
        for (roots.items) |r| a.free(r);
        roots.deinit(a);
    }

    if (roots.items.len == 0) {
        std.debug.print("checksums: nothing to do (no third_party assets yet)\n", .{});
        return;
    }

    for (roots.items) |root_abs| {
        try writeChecksumsFor(a, root_abs);
        std.debug.print("checksums: wrote {s}/CHECKSUMS.sha256\n", .{root_abs});
    }
}

pub fn verifyAll(a: std.mem.Allocator) !void {
    var roots = try discoverVersionRoots(a);
    defer {
        for (roots.items) |r| a.free(r);
        roots.deinit(a);
    }

    if (roots.items.len == 0) {
        std.debug.print("verify: nothing to check (no third_party assets yet)\n", .{});
        return;
    }

    for (roots.items) |root_abs| {
        try verifyOne(a, root_abs);
    }
}

fn bytesToHexLower(a: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const lut = "0123456789abcdef";
    var out = try a.alloc(u8, bytes.len * 2);
    var j: usize = 0;
    for (bytes) |b| {
        out[j] = lut[(b >> 4) & 0xF];
        out[j + 1] = lut[b & 0xF];
        j += 2;
    }
    return out;
}

// ─────────────────────────────────────────────────────────────
// Freeze lock
// ─────────────────────────────────────────────────────────────

fn latestByMtime(a: std.mem.Allocator, dir_abs: []const u8) !?[]const u8 {
    var dir = try std.fs.cwd().openDir(dir_abs, .{ .iterate = true, .access_sub_paths = true });
    defer dir.close();

    var it = dir.iterate();
    var best: ?struct { name: []const u8, mtime: i128 } = null;

    while (try it.next()) |e| {
        if (e.kind != .directory) continue;
        if (e.name.len == 0 or e.name[0] == '.') continue;
        if (std.mem.eql(u8, e.name, "node_modules")) continue;

        const sub_abs = try std.fs.path.join(a, &.{ dir_abs, e.name });
        defer a.free(sub_abs);

        var files = std.ArrayList([]const u8){};
        defer {
            for (files.items) |p| a.free(p);
            files.deinit(a);
        }
        try walkFilesCollect(a, sub_abs, &files);
        if (files.items.len == 0) continue;

        const st = std.fs.cwd().statFile(sub_abs) catch {
            if (best == null or std.mem.lessThan(u8, best.?.name, e.name)) {
                best = .{ .name = try a.dupe(u8, e.name), .mtime = 0 };
            }
            continue;
        };
        const m = st.mtime;
        if (best == null or m > best.?.mtime) {
            best = .{ .name = try a.dupe(u8, e.name), .mtime = m };
        }
    }

    if (best == null) return null;
    return best.?.name;
}

fn jsonEscapeInto(w: anytype, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        else => try w.writeByte(c),
    };
}

fn freezeLock(a: std.mem.Allocator) !void {
    const root = "third_party";

    var tp = std.fs.cwd().openDir(root, .{ .iterate = true }) catch |e| {
        if (e == error.FileNotFound) {
            std.debug.print("freeze: nothing to freeze (no third_party)\n", .{});
            return;
        }
        return e;
    };
    defer tp.close();

    var it = tp.iterate();

    var entries = std.ArrayList(struct { key: []const u8, val: []const u8 }){};
    defer {
        for (entries.items) |kv| {
            a.free(kv.key);
            a.free(kv.val);
        }
        entries.deinit(a);
    }

    while (try it.next()) |e| {
        if (e.kind != .directory) continue;
        if (e.name.len == 0 or e.name[0] == '.') continue;

        const fam_abs = try std.fs.path.join(a, &.{ root, e.name });
        defer a.free(fam_abs);

        const vopt = try latestByMtime(a, fam_abs);
        if (vopt) |vname| {
            try entries.append(a, .{ .key = try a.dupe(u8, e.name), .val = vname });
        }
    }

    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    var w = buf.writer();

    try w.writeAll("{");
    var first = true;
    for (entries.items) |kv| {
        if (!first) try w.writeAll(", ");
        first = false;

        try w.writeByte('"');
        try jsonEscapeInto(w, kv.key);
        try w.writeByte('"');
        try w.writeAll(": ");
        try w.writeByte('"');
        try jsonEscapeInto(w, kv.val);
        try w.writeByte('"');
    }
    try w.writeAll("}\n");

    const lock_path = try std.fs.path.join(a, &.{ root, "VENDOR.lock" });
    defer a.free(lock_path);
    try writeTextFile(lock_path, buf.items);

    std.debug.print("freeze: wrote {s}\n", .{lock_path});
}

// ─────────────────────────────────────────────────────────────
// Bootstrap (config-driven)
// ─────────────────────────────────────────────────────────────

fn parseKvConfig(a: std.mem.Allocator, path: []const u8) !std.StringHashMap([]const u8) {
    var map = std.StringHashMap([]const u8).init(a);

    const buf = try slurpFile(a, path, 1 << 16);
    defer a.free(buf);

    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |raw| {
        const ln = std.mem.trim(u8, raw, " \t\r");
        if (ln.len == 0 or ln[0] == '#') continue;

        const eq = std.mem.indexOfScalar(u8, ln, '=') orelse continue;
        const k = std.mem.trim(u8, ln[0..eq], " \t");
        const v = std.mem.trim(u8, ln[eq + 1 ..], " \t");
        if (k.len == 0) continue;

        try map.put(try a.dupe(u8, k), try a.dupe(u8, v));
    }
    return map;
}

fn get(map: *const std.StringHashMap([]const u8), key: []const u8) ?[]const u8 {
    return map.get(key);
}

fn sub_bootstrap(a: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    var cfg_path: []const u8 = "tools/vendor.config";
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--config")) {
            cfg_path = it.next() orelse {
                std.debug.print("bootstrap: --config requires a path\n", .{});
                return error.Invalid;
            };
        } else {
            std.debug.print("bootstrap: unknown option {s}\n", .{arg});
            return error.Invalid;
        }
    }

    var map = parseKvConfig(a, cfg_path) catch |e| {
        if (e == error.FileNotFound) {
            std.debug.print("bootstrap: no config at {s}; nothing to do\n", .{cfg_path});
            return;
        }
        return e;
    };
    defer {
        var itx = map.iterator();
        while (itx.next()) |ent| {
            a.free(ent.key_ptr.*);
            a.free(ent.value_ptr.*);
        }
        map.deinit();
    }

    var did_any: bool = false;

    if (get(&map, "katex.version")) |k_ver| {
        const k_mf = get(&map, "katex.manifest") orelse {
            std.debug.print("bootstrap: katex.version set but katex.manifest missing\n", .{});
            return error.Invalid;
        };
        const k_cdn = get(&map, "katex.cdn") orelse "jsdelivr";
        try fetchKatex(a, k_ver, k_mf, k_cdn);
        did_any = true;
    }

    if (get(&map, "tailwind.version")) |t_ver| {
        const t_url = get(&map, "tailwind.url") orelse {
            std.debug.print("bootstrap: tailwind.version set but tailwind.url missing\n", .{});
            return error.Invalid;
        };
        try fetchTailwindTheme(a, t_ver, t_url);
        did_any = true;
    }

    try writeAllChecksums(a);
    try freezeLock(a);
    try verifyAll(a);

    if (!did_any)
        std.debug.print("bootstrap: config had no vendor entries; wrote/checked nothing\n", .{})
    else
        std.debug.print("bootstrap: done\n", .{});
}
