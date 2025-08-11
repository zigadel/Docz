const std = @import("std");
const docz = @import("docz");

pub fn run(alloc: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    // Defaults
    var doc_root: []const u8 = ".";
    var port: u16 = 5173;
    var path: []const u8 = "docs/SPEC.dcz";
    var have_positional = false;

    // Parse: [<path>] [--root|-r DIR] [--port|-p N] [--help|-h]
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
            port = std.fmt.parseUnsigned(u16, v, 10) catch {
                std.debug.print("preview: invalid port: {s}\n", .{v});
                return error.Invalid;
            };
        } else if (arg.len > 0 and arg[0] != '-') {
            if (have_positional) {
                std.debug.print("preview: unknown arg: {s}\n", .{arg});
                return error.Invalid;
            }
            path = arg;
            have_positional = true;
        } else {
            std.debug.print("preview: unknown arg: {s}\n", .{arg});
            return error.Invalid;
        }
    }

    // Start server
    var server = try docz.web_preview.server.PreviewServer.init(alloc, doc_root);
    defer server.deinit();

    // Open the browser (best-effort, non-blocking)
    try openBrowser(alloc, port, path);

    // Block and serve
    try server.listenAndServe(port);
}

fn openBrowser(alloc: std.mem.Allocator, port: u16, path: []const u8) !void {
    const url = try std.fmt.allocPrint(alloc, "http://127.0.0.1:{d}/view?path={s}", .{ port, path });
    defer alloc.free(url);

    const os = @import("builtin").os.tag;
    const argv = switch (os) {
        .windows => &[_][]const u8{ "cmd", "/c", "start", url },
        .macos => &[_][]const u8{ "open", url },
        else => &[_][]const u8{ "xdg-open", url },
    };

    var child = std.process.Child.init(argv, alloc);
    _ = child.spawn() catch {}; // best-effort; ignore failures
}

fn printUsage() void {
    std.debug.print(
        \\Usage: docz preview [<path>] [--root <dir>] [--port <num>]
        \\
        \\Options:
        \\  <path>            .dcz to open initially (default: docs/SPEC.dcz)
        \\  -r, --root <dir>  Document root to serve   (default: ".")
        \\  -p, --port <num>  Port to listen on        (default: 5173)
        \\  -h, --help        Show this help
        \\
        \\Examples:
        \\  docz preview
        \\  docz preview docs/SPEC.dcz
        \\  docz preview --root docs --port 8787 docs/guide.dcz
        \\
    , .{});
}

test "preview.cli compiles and usage prints" {
    // Smoke test: just call printUsage; nothing to assert.
    printUsage();
}
