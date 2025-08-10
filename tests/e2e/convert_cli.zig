const std = @import("std");
const builtin = @import("builtin");

fn exeName() []const u8 {
    return if (builtin.os.tag == .windows) "docz.exe" else "docz";
}

fn e2eExeName() []const u8 {
    return if (builtin.os.tag == .windows) "docz-e2e.exe" else "docz-e2e";
}

fn pathJoin2(alloc: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    var list = std.ArrayList([]const u8).init(alloc);
    defer list.deinit();
    try list.append(a);
    try list.append(b);
    return std.fs.path.join(alloc, list.items);
}

/// Build an absolute path to a file under zig-out/bin without requiring it to exist.
fn binPathAbs(alloc: std.mem.Allocator, name: []const u8) ![]u8 {
    const cwd_abs = try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(cwd_abs);

    const rel = try pathJoin2(alloc, "zig-out/bin", name);
    defer alloc.free(rel);

    return try pathJoin2(alloc, cwd_abs, rel);
}

fn fileExistsAbsolute(path: []const u8) bool {
    if (std.fs.openFileAbsolute(path, .{})) |f| {
        f.close();
        return true;
    } else |_| {
        return false;
    }
}

fn copyFileAbs(src_path: []const u8, dst_path: []const u8) !void {
    var src = try std.fs.openFileAbsolute(src_path, .{});
    defer src.close();

    var dst = try std.fs.createFileAbsolute(dst_path, .{ .truncate = true });
    defer dst.close();

    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try src.read(&buf);
        if (n == 0) break;
        try dst.writeAll(buf[0..n]);
    }
}

/// Ensure a dedicated launcher (copy of docz) so install step can overwrite docz.exe later on Windows.
fn ensureE2eLauncher(alloc: std.mem.Allocator) ![]u8 {
    const e2e = try binPathAbs(alloc, e2eExeName());
    if (fileExistsAbsolute(e2e)) return e2e;

    const docz = try binPathAbs(alloc, exeName());
    if (!fileExistsAbsolute(docz)) return error.FileNotFound;

    try copyFileAbs(docz, e2e);
    return e2e;
}

/// Create a fresh working directory under zig-out/ and return both an open Dir and its absolute path.
fn makeWorkDir(alloc: std.mem.Allocator) !struct { dir: std.fs.Dir, abs: []u8 } {
    try std.fs.cwd().makePath("zig-out");

    var zig_out = try std.fs.cwd().openDir("zig-out", .{ .iterate = false });
    defer zig_out.close();

    var name_buf: [64]u8 = undefined;
    const sub = try std.fmt.bufPrint(&name_buf, "e2e_cli_test-{d}", .{std.time.milliTimestamp()});
    try zig_out.makePath(sub);

    // Get absolute path to zig-out, then build the final absolute work path.
    const zig_out_abs = try std.fs.cwd().realpathAlloc(alloc, "zig-out");
    const work_abs = try pathJoin2(alloc, zig_out_abs, sub);
    alloc.free(zig_out_abs); // <— free on success too

    const work_dir = try zig_out.openDir(sub, .{ .iterate = false });

    return .{ .dir = work_dir, .abs = work_abs };
}

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

    // workspace
    var work_bundle = try makeWorkDir(A);
    defer {
        work_bundle.dir.close();
        A.free(work_bundle.abs);
    }
    const work = work_bundle.dir;
    const work_abs = work_bundle.abs;

    // Absolute file paths we’ll pass to the child process
    const in_path = try pathJoin2(A, work_abs, "in.dcz");
    defer A.free(in_path);
    const out_path = try pathJoin2(A, work_abs, "out.tex");
    defer A.free(out_path);
    const back_path = try pathJoin2(A, work_abs, "back.dcz");
    defer A.free(back_path);

    // write in.dcz (via the Dir handle; independent of child CWD)
    {
        var f = try work.createFile("in.dcz", .{ .truncate = true });
        defer f.close();
        _ = try f.writeAll(dcz_input);
    }

    const exe_path = try ensureE2eLauncher(A);
    defer A.free(exe_path);

    // docz convert <abs in> --to <abs out>
    {
        var child = std.process.Child.init(
            &[_][]const u8{ exe_path, "convert", in_path, "--to", out_path },
            A,
        );
        // No cwd_dir / cwd dependency anymore
        try child.spawn();
        const term = try child.wait();
        try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, term);
    }

    // read out.tex and sanity-check
    const tex = blk: {
        var f = try work.openFile("out.tex", .{});
        defer f.close();
        break :blk try f.readToEndAlloc(A, 1 << 20);
    };
    defer A.free(tex);

    try std.testing.expect(std.mem.indexOf(u8, tex, "\\title{T}") != null);
    try std.testing.expect(std.mem.indexOf(u8, tex, "\\section{Hello}") != null);

    // round-trip back: docz convert <abs out.tex> --to <abs back.dcz>
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
        break :blk2 try f.readToEndAlloc(A, 1 << 20);
    };
    defer A.free(back);

    try std.testing.expect(std.mem.indexOf(u8, back, "@heading(level=1) Hello @end") != null);
}
