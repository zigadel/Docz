const std = @import("std");

/// Minimal, stable helper used by integration/e2e to hash a manifest file.
/// This is a placeholder implementation that can be evolved later.
pub fn sha256File(allocator: std.mem.Allocator, path: []const u8) ![32]u8 {
    const bytes = try std.fs.cwd().readFileAlloc(path, allocator, 1 << 26);
    defer allocator.free(bytes);
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &out);
    return out;
}

pub fn hexLower(b: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const s = try allocator.alloc(u8, b.len * 2);
    _ = std.fmt.bufPrint(s, "{s}", .{std.fmt.fmtSliceHexLower(b)}) catch unreachable;
    return s;
}

test "sha256File exists-or-empty semantics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    // Create a temp file
    var tmp = try std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const p = "m.txt";
    try tmp.dir.writeFile(p, "abc");

    var h = try sha256File(A, try tmp.dir.realpathAlloc(A, p));
    // Known sha256("abc")
    const expected = [_]u8{ 0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23, 0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c, 0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad };
    try std.testing.expect(std.mem.eql(u8, &h, &expected));
}
