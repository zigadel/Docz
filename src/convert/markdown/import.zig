const std = @import("std");

pub fn importMarkdownToDcz(allocator: std.mem.Allocator, md: []const u8) ![]u8 {
    // Tiny placeholder: turn "# Title" into @heading, blank lines into paragraph breaks.
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const w = out.writer();

    var it = std.mem.splitScalar(u8, md, '\n');
    while (it.next()) |line_in| {
        const line = std.mem.trim(u8, line_in, " \t\r");
        if (line.len == 0) {
            // blank -> paragraph break; keep simple for demo
            _ = try w.write("\n");
            continue;
        }
        if (std.mem.startsWith(u8, line, "# ")) {
            try w.print("@heading(level=1) {s} @end\n", .{line[2..]});
        } else if (std.mem.startsWith(u8, line, "## ")) {
            try w.print("@heading(level=2) {s} @end\n", .{line[3..]});
        } else {
            try w.print("{s}\n", .{line});
        }
    }

    return out.toOwnedSlice();
}

// -----------------
// Unit tests (in-file)
// -----------------
test "markdown import: basic headings + paragraph" {
    const md =
        \\# Title
        \\para line
        \\## Sub
        \\more text
        \\
    ;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    const out = try importMarkdownToDcz(A, md);
    defer A.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "@heading(level=1) Title @end") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "para line\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@heading(level=2) Sub @end") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "more text\n") != null);
}
