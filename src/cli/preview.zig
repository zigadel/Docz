const std = @import("std");
const docz = @import("docz");
const web_preview = @import("web_preview");

// -----------------------------------------------------------------------------
// Tiny settings loader (flat JSON, no std.json dependency)
// Reads: root (string), port (int), open (bool). CLI flags override these.
// -----------------------------------------------------------------------------

const FileSettings = struct {
    root: []const u8 = ".",
    port: u16 = 5173,
    open: bool = true,
};

fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    // Zig 0.16: Dir.readFileAlloc(path, allocator, Io.Limit)
    return std.fs.cwd().readFileAlloc(path, alloc, @enumFromInt(max));
}

fn skipWs(buf: []const u8, start: usize) usize {
    var i = start;
    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    return i;
}

fn findJsonStringValue(buf: []const u8, key: []const u8) ?[]const u8 {
    // Build the `"key"` pattern using a tiny fixed buffer (no heap leaks).
    var pat_buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&pat_buf);
    const A = fba.allocator();
    const quoted_key = std.fmt.allocPrint(A, "\"{s}\"", .{key}) catch return null;

    const key_i = std.mem.indexOf(u8, buf, quoted_key) orelse return null;
    var i: usize = key_i + quoted_key.len;

    i = skipWs(buf, i);
    if (i >= buf.len or buf[i] != ':') return null;
    i += 1;

    i = skipWs(buf, i);
    if (i >= buf.len or buf[i] != '"') return null;
    i += 1;

    const start = i;
    while (i < buf.len and buf[i] != '"') : (i += 1) {}
    if (i >= buf.len) return null;

    return buf[start..i];
}

fn findJsonIntValue(comptime T: type, buf: []const u8, key: []const u8) ?T {
    var pat_buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&pat_buf);
    const A = fba.allocator();
    const quoted_key = std.fmt.allocPrint(A, "\"{s}\"", .{key}) catch return null;

    const key_i = std.mem.indexOf(u8, buf, quoted_key) orelse return null;
    var i: usize = key_i + quoted_key.len;

    i = skipWs(buf, i);
    if (i >= buf.len or buf[i] != ':') return null;
    i += 1;

    i = skipWs(buf, i);
    if (i >= buf.len) return null;

    const start = i;
    while (i < buf.len and (buf[i] >= '0' and buf[i] <= '9')) : (i += 1) {}
    if (i == start) return null;

    return std.fmt.parseInt(T, buf[start..i], 10) catch null;
}

fn findJsonBoolValue(buf: []const u8, key: []const u8) ?bool {
    var pat_buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&pat_buf);
    const A = fba.allocator();
    const quoted_key = std.fmt.allocPrint(A, "\"{s}\"", .{key}) catch return null;

    const key_i = std.mem.indexOf(u8, buf, quoted_key) orelse return null;
    var i: usize = key_i + quoted_key.len;

    i = skipWs(buf, i);
    if (i >= buf.len or buf[i] != ':') return null;
    i += 1;

    i = skipWs(buf, i);
    if (i >= buf.len) return null;

    if (std.mem.startsWith(u8, buf[i..], "true")) return true;
    if (std.mem.startsWith(u8, buf[i..], "false")) return false;
    return null;
}

fn loadFileSettings(alloc: std.mem.Allocator, path_opt: ?[]const u8) !FileSettings {
    var s: FileSettings = .{};
    const path = path_opt orelse "docz.settings.json";

    const buf = readFileAlloc(alloc, path, 1 << 16) catch |e| {
        if (e == error.FileNotFound) return s; // defaults if missing
        return e;
    };
    defer alloc.free(buf);

    if (findJsonStringValue(buf, "root")) |v| s.root = try alloc.dupe(u8, v);
    if (findJsonIntValue(u16, buf, "port")) |p| s.port = p;
    if (findJsonBoolValue(buf, "open")) |b| s.open = b;

    return s;
}

// -----------------------------------------------------------------------------
// URL helpers
// -----------------------------------------------------------------------------

fn isUnreserved(ch: u8) bool {
    return (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '-' or ch == '_' or ch == '.' or ch == '~' or ch == '/'; // keep slashes in path
}

fn urlEncode(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    // Worst-case 3x expansion
    var out = try alloc.alloc(u8, s.len * 3);
    var j: usize = 0;

    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (isUnreserved(c)) {
            out[j] = c;
            j += 1;
        } else {
            out[j + 0] = '%';
            out[j + 1] = "0123456789ABCDEF"[(c >> 4) & 0xF];
            out[j + 2] = "0123456789ABCDEF"[c & 0xF];
            j += 3;
        }
    }
    return alloc.realloc(out, j);
}

// -----------------------------------------------------------------------------
// CLI
// -----------------------------------------------------------------------------

pub fn run(alloc: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    // Defaults (overridden by config file if present, and then by CLI flags)
    var cfg_path: ?[]const u8 = null;
    var fs = try loadFileSettings(alloc, cfg_path);

    var doc_root: []const u8 = fs.root;
    var port: u16 = fs.port;
    var open_browser: bool = fs.open;

    var path: []const u8 = "docs/SPEC.dcz";
    var have_positional = false;

    // Parse: [<path>] [--root|-r DIR] [--port|-p N] [--no-open] [--config <file>] [--help|-h]
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return printUsage();
        } else if (std.mem.eql(u8, arg, "--config")) {
            const v = it.next() orelse {
                std.debug.print("preview: --config requires a value\n", .{});
                return error.Invalid;
            };
            cfg_path = v;
            fs = try loadFileSettings(alloc, cfg_path);
            // Re-apply config defaults unless already overridden by flags seen earlier
            doc_root = fs.root;
            port = fs.port;
            open_browser = fs.open;
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
            port = std.fmt.parseInt(u16, v, 10) catch {
                std.debug.print("preview: invalid port: {s}\n", .{v});
                return error.Invalid;
            };
        } else if (std.mem.eql(u8, arg, "--no-open")) {
            open_browser = false;
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

    // Start server (module is `web_preview`; type is `PreviewServer`)
    var server = try web_preview.PreviewServer.init(alloc, doc_root);
    defer server.deinit();

    // Optionally open the browser
    if (open_browser) {
        try openBrowser(alloc, port, path);
    }

    // Block and serve
    try server.listenAndServe(port);
}

fn openBrowser(alloc: std.mem.Allocator, port: u16, path: []const u8) !void {
    // Always navigate via the view endpoint so Docz renders .dcz directly.
    const enc = try urlEncode(alloc, path);
    defer alloc.free(enc);

    const url = try std.fmt.allocPrint(alloc, "http://127.0.0.1:{d}/view?path={s}", .{ port, enc });
    defer alloc.free(url);

    const os = @import("builtin").os.tag;
    const argv = switch (os) {
        .windows => &[_][]const u8{ "cmd", "/c", "start", "", url }, // empty title
        .macos => &[_][]const u8{ "open", url },
        else => &[_][]const u8{ "xdg-open", url },
    };

    var child = std.process.Child.init(argv, alloc);
    _ = child.spawn() catch {}; // best-effort; ignore failures
}

fn printUsage() void {
    std.debug.print(
        \\Usage: docz preview [<path>] [--root <dir>] [--port <num>] [--no-open] [--config <file>]
        \\
        \\Options:
        \\  <path>            .dcz to open initially (default: docs/SPEC.dcz)
        \\  -r, --root <dir>  Document root to serve   (default: ".", or from config)
        \\  -p, --port <num>  Port to listen on        (default: 5173, or from config)
        \\      --no-open     Do not open a browser (useful when spawned by `docz run`)
        \\      --config      Path to a settings JSON (default: docz.settings.json if present)
        \\  -h, --help        Show this help
        \\
        \\Examples:
        \\  docz preview
        \\  docz preview docs/SPEC.dcz
        \\  docz preview --root docs --port 8787 docs/guide.dcz
        \\  docz preview --config my.settings.json
        \\
    , .{});
}

test "preview.cli compiles and usage prints" {
    // Smoke test: just call printUsage; nothing to assert.
    printUsage();
}
