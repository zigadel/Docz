const std = @import("std");
const docz = @import("docz");

pub fn run(alloc: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    // Defaults
    var doc_root: []const u8 = ".";
    var port: u16 = 5173;

    // Parse flags: --root/-r, --port/-p, --help/-h
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return printUsage();
        } else if (std.mem.eql(u8, arg, "--root") or std.mem.eql(u8, arg, "-r")) {
            const v = it.next() orelse {
                std.debug.print("preview: --root requires a value\n", .{});
                return error.Invalid;
            };
            doc_root = v;
        } else if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
            const v = it.next() orelse {
                std.debug.print("preview: --port requires a value\n", .{});
                return error.Invalid;
            };
            const parsed = std.fmt.parseUnsigned(u16, v, 10) catch {
                std.debug.print("preview: invalid port: {s}\n", .{v});
                return error.Invalid;
            };
            port = parsed;
        } else {
            std.debug.print("preview: unknown arg: {s}\n", .{arg});
            return error.Invalid;
        }
    }

    // Start server
    var server = try docz.web_preview.server.PreviewServer.init(alloc, doc_root);
    defer server.deinit();

    try server.listenAndServe(port);
}

fn printUsage() void {
    std.debug.print(
        \\Usage: docz preview [--root <dir>] [--port <num>]
        \\
        \\Options:
        \\  -r, --root <dir>   Document root to serve   (default: ".")
        \\  -p, --port <num>   Port to listen on        (default: 5173)
        \\  -h, --help         Show this help
        \\
        \\Examples:
        \\  docz preview
        \\  docz preview --root docs --port 5173
        \\
    , .{});
}

test "preview.cli compiles and usage prints" {
    // Smoke test: just call printUsage; nothing to assert.
    printUsage();
}
