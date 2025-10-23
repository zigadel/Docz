const std = @import("std");

/// Filesystem + hashing utilities extracted from your original tools/vendor.zig,
/// trimmed to only what verifyAll() needs. No HTTP symbols.
pub const IGNORE_BASENAMES = [_][]const u8{
    "CHECKSUMS.sha256",
    "VERSION",
    ".DS_Store",
    "Thumbs.db",
};

pub fn isIgnoredBase(b: []const u8) bool {
    for (IGNORE_BASENAMES) |name| if (std.mem.eql(u8, b, name)) return true;
    return false;
}

pub fn walkFilesCollect(a: std.mem.Allocator, root_abs: []const u8, out: *std.ArrayList([]const u8)) !void {
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

pub fn sha256HexOfFile(a: std.mem.Allocator, abs: []const u8) ![]u8 {
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

pub fn writeChecksumsFor(a: std.mem.Allocator, base_abs: []const u8) !void {
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

pub fn verifyOne(a: std.mem.Allocator, base_abs: []const u8) !void {
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

pub fn discoverVersionRoots(a: std.mem.Allocator) !std.ArrayList([]const u8) {
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

// ---- tiny IO helpers (no HTTP) ----

pub fn slurpFile(a: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
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

pub fn fileExists(abs: []const u8) bool {
    _ = std.fs.cwd().access(abs, .{}) catch return false;
    return true;
}

pub fn bytesToHexLower(a: std.mem.Allocator, bytes: []const u8) ![]u8 {
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
