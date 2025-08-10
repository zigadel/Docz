const std = @import("std");
const builtin = @import("builtin");

fn exeName() []const u8 {
    return if (builtin.os.tag == .windows) "docz.exe" else "docz";
}

fn pathJoin2(alloc: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    var list = std.ArrayList([]const u8).init(alloc);
    defer list.deinit();
    try list.append(a);
    try list.append(b);
    return std.fs.path.join(alloc, list.items);
}

// Build absolute path: zig-out/bin/docz[.exe]
fn doczPathAbs(alloc: std.mem.Allocator) ![]u8 {
    const rel = try pathJoin2(alloc, "zig-out/bin", exeName());
    defer alloc.free(rel);
    return std.fs.cwd().realpathAlloc(alloc, rel);
}

// Make a deterministic per-run directory under zig-out/ (no RNG needed)
// Make a deterministic per-run directory under zig-out/ (no RNG needed)
fn makeWorkDir() !std.fs.Dir {
    // ensure zig-out exists
    try std.fs.cwd().makePath("zig-out");

    // open zig-out
    var zig_out = try std.fs.cwd().openDir("zig-out", .{ .iterate = false });
    defer zig_out.close();

    // per-run subdir name (timestamp-based)
    var name_buf: [64]u8 = undefined;
    const sub = try std.fmt.bufPrint(&name_buf, "e2e_cli_test-{d}", .{std.time.milliTimestamp()});

    // create the subdir and return an open handle to it
    try zig_out.makePath(sub);
    return zig_out.openDir(sub, .{ .iterate = false });
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

    // workspace under zig-out/
    var work = try makeWorkDir();
    defer work.close();

    // write in.dcz
    {
        var f = try work.createFile("in.dcz", .{ .truncate = true });
        defer f.close();
        _ = try f.writeAll(dcz_input);
    }

    const exe_path = try doczPathAbs(A);
    defer A.free(exe_path);

    // docz convert in.dcz --to out.tex
    {
        var child = std.process.Child.init(
            &[_][]const u8{ exe_path, "convert", "in.dcz", "--to", "out.tex" },
            A,
        );
        child.cwd_dir = work;
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

    // round-trip back: docz convert out.tex --to back.dcz
    {
        var child = std.process.Child.init(
            &[_][]const u8{ exe_path, "convert", "out.tex", "--to", "back.dcz" },
            A,
        );
        child.cwd_dir = work;
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
