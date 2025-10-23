const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

// ─────────────────────────────────────────────────────────────────────────────
// Small path helpers (owned results)
// ─────────────────────────────────────────────────────────────────────────────

fn pathJoin2(alloc: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    var list = std.ArrayList([]const u8){};
    defer list.deinit(alloc);
    try list.append(alloc, a);
    try list.append(alloc, b);
    return std.fs.path.join(alloc, list.items);
}

fn pathJoin3(alloc: std.mem.Allocator, a: []const u8, b: []const u8, c: []const u8) ![]u8 {
    var list = std.ArrayList([]const u8){};
    defer list.deinit(alloc);
    try list.append(alloc, a);
    try list.append(alloc, b);
    try list.append(alloc, c);
    return std.fs.path.join(alloc, list.items);
}

fn dirExistsAbs(abs_path: []const u8) bool {
    var d = std.fs.openDirAbsolute(abs_path, .{}) catch return false;
    d.close();
    return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Repo/CWD anchor (stable for test runner)
// ─────────────────────────────────────────────────────────────────────────────

fn repoRootFromCwd(alloc: std.mem.Allocator) ![]u8 {
    return std.fs.cwd().realpathAlloc(alloc, ".");
}

// ─────────────────────────────────────────────────────────────────────────────
// Launcher discovery (no nested functions)
// ─────────────────────────────────────────────────────────────────────────────

fn tryOpenAbs(p: []const u8) bool {
    if (!std.fs.path.isAbsolute(p)) return false;
    const f = std.fs.openFileAbsolute(p, .{}) catch return false;
    f.close();
    return true;
}

fn findUpFile(
    alloc: std.mem.Allocator,
    start_abs: []const u8,
    rel: []const u8,
    max_up: usize,
) !?[]u8 {
    if (!std.fs.path.isAbsolute(start_abs)) return null;

    var cur = try alloc.dupe(u8, start_abs);
    defer alloc.free(cur);

    var i: usize = 0;
    while (true) : (i += 1) {
        if (i > max_up) break;

        const cand = try std.fs.path.join(alloc, &[_][]const u8{ cur, rel });
        if (std.fs.openFileAbsolute(cand, .{})) |f| {
            f.close();
            return cand; // owned
        } else |e| {
            switch (e) {
                error.FileNotFound => {},
                else => {},
            }
        }
        alloc.free(cand);

        const parent_opt = std.fs.path.dirname(cur);
        if (parent_opt == null) break;

        const parent = parent_opt.?;
        const dup = try alloc.dupe(u8, parent);
        alloc.free(cur);
        cur = dup;
    }
    return null;
}

fn ensureE2ELauncher(alloc: std.mem.Allocator) ![]u8 {
    const e2e_name = if (builtin.os.tag == .windows) "docz-e2e.exe" else "docz-e2e";
    const docz_name = if (builtin.os.tag == .windows) "docz.exe" else "docz";

    if (@hasDecl(build_options, "e2e_abspath")) {
        const baked = build_options.e2e_abspath;
        if (tryOpenAbs(baked)) return try alloc.dupe(u8, baked);
    }

    const cwd_abs = try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(cwd_abs);

    const rel_e2e = try std.fs.path.join(alloc, &[_][]const u8{ "zig-out", "bin", e2e_name });
    defer alloc.free(rel_e2e);
    if (try findUpFile(alloc, cwd_abs, rel_e2e, 8)) |hit| return hit;

    const rel_docz = try std.fs.path.join(alloc, &[_][]const u8{ "zig-out", "bin", docz_name });
    defer alloc.free(rel_docz);
    if (try findUpFile(alloc, cwd_abs, rel_docz, 8)) |hit| return hit;

    if (@hasDecl(build_options, "docz_abspath")) {
        const baked_docz = build_options.docz_abspath;
        if (tryOpenAbs(baked_docz)) return try alloc.dupe(u8, baked_docz);
    }

    std.debug.print(
        "[ensureE2ELauncher] Could not find a runnable CLI.\n" ++
            "  Tried (in order):\n" ++
            "    • build_options.e2e_abspath\n" ++
            "    • find-up from CWD for zig-out/bin/{s}\n" ++
            "    • find-up from CWD for zig-out/bin/{s}\n" ++
            "    • build_options.docz_abspath\n",
        .{ e2e_name, docz_name },
    );

    return error.FileNotFound;
}

// ─────────────────────────────────────────────────────────────────────────────
// Test workspace helper (under <repo>/zig-out)
// ─────────────────────────────────────────────────────────────────────────────

fn makeWorkDir(alloc: std.mem.Allocator) !struct { dir: std.fs.Dir, abs: []u8 } {
    const repo_abs = try repoRootFromCwd(alloc);
    defer alloc.free(repo_abs);

    const base_abs = if (dirExistsAbs(repo_abs))
        try alloc.dupe(u8, repo_abs)
    else
        try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(base_abs);

    var base_dir = try std.fs.openDirAbsolute(base_abs, .{});
    defer base_dir.close();

    try base_dir.makePath("zig-out");

    var name_buf: [64]u8 = undefined;
    const sub = try std.fmt.bufPrint(&name_buf, "e2e_cli_test-{d}", .{std.time.milliTimestamp()});
    const sub_rel = try std.fs.path.join(alloc, &[_][]const u8{ "zig-out", sub });
    defer alloc.free(sub_rel);

    try base_dir.makePath(sub_rel);

    const abs = try pathJoin3(alloc, base_abs, "zig-out", sub);
    const dir = try std.fs.openDirAbsolute(abs, .{ .iterate = false });

    return .{ .dir = dir, .abs = abs };
}

// ─────────────────────────────────────────────────────────────────────────────
// The actual e2e test
// ─────────────────────────────────────────────────────────────────────────────

test "e2e: docz convert dcz→tex and tex→dcz" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const dcz_input =
        \\@meta(title="T") @end
        \\@heading(level=1) Hello @end
        \\Para
        \\
    ;

    var work_bundle = try makeWorkDir(A);
    defer {
        work_bundle.dir.close();
        A.free(work_bundle.abs);
    }
    const work = work_bundle.dir;
    const work_abs = work_bundle.abs;

    const in_path = try pathJoin2(A, work_abs, "in.dcz");
    defer A.free(in_path);
    const out_path = try pathJoin2(A, work_abs, "out.tex");
    defer A.free(out_path);
    const back_path = try pathJoin2(A, work_abs, "back.dcz");
    defer A.free(back_path);

    {
        var f = try work.createFile("in.dcz", .{ .truncate = true });
        defer f.close();
        _ = try f.writeAll(dcz_input);
    }

    const exe_path = try ensureE2ELauncher(A);
    defer A.free(exe_path);

    {
        var child = std.process.Child.init(
            &[_][]const u8{ exe_path, "convert", in_path, "--to", out_path },
            A,
        );
        try child.spawn();
        const term = try child.wait();
        try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, term);
    }

    const tex = blk: {
        var f = try work.openFile("out.tex", .{});
        defer f.close();

        var out = std.ArrayList(u8){};
        defer out.deinit(A);
        var tmp: [4096]u8 = undefined;
        while (true) {
            const n = try f.read(&tmp);
            if (n == 0) break;
            try out.appendSlice(A, tmp[0..n]);
        }
        break :blk try out.toOwnedSlice(A);
    };
    defer A.free(tex);

    try std.testing.expect(std.mem.indexOf(u8, tex, "\\title{T}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\section{Hello}") != null);

    {
        var child = std.process.Child.init(
            &[_][]const u8{ exe_path, "convert", out_path, "--to", back_path },
            A,
        );
        try child.spawn();
        const term = try child.wait();
        try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, term);
    }

    const back = blk2: {
        var f = try work.openFile("back.dcz", .{});
        defer f.close();

        var out = std.ArrayList(u8){};
        defer out.deinit(A);
        var tmp: [4096]u8 = undefined;
        while (true) {
            const n = try f.read(&tmp);
            if (n == 0) break;
            try out.appendSlice(A, tmp[0..n]);
        }
        break :blk2 try out.toOwnedSlice(A);
    };
    defer A.free(back);

    try std.testing.expect(std.mem.indexOf(u8, back, "@heading(level=1) Hello @end") != null);
}
