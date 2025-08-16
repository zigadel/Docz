const std = @import("std");

pub const Kind = enum { dcz, md, html, tex };

// ---------- stderr helper ----------
fn errW() std.fs.File.Writer {
    var f = std.fs.File{ .handle = std.io.getStdErrHandle() };
    return f.writer();
}

// ---------- file helpers ----------
pub fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    return try f.readToEndAlloc(alloc, 1 << 26);
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    const cwd = std.fs.cwd();
    if (std.fs.path.dirname(path)) |dirpart| {
        try cwd.makePath(dirpart);
    }
    var f = try cwd.createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}

// ---------- kind detection ----------
pub fn detectKindFromPath(p: []const u8) ?Kind {
    const ext = std.fs.path.extension(p);
    if (ext.len == 0) return null;
    if (std.ascii.eqlIgnoreCase(ext, ".dcz")) return .dcz;
    if (std.ascii.eqlIgnoreCase(ext, ".md")) return .md;
    if (std.ascii.eqlIgnoreCase(ext, ".html") or std.ascii.eqlIgnoreCase(ext, ".htm")) return .html;
    if (std.ascii.eqlIgnoreCase(ext, ".tex")) return .tex;
    return null;
}

// ---------- tiny arg helper used by convert CLI ----------
pub fn parseTo(it: *std.process.ArgIterator) !?[]const u8 {
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--to") or std.mem.eql(u8, arg, "-t")) {
            return it.next() orelse {
                try errW().writeAll("--to requires a value\n");
                return error.Invalid;
            };
        } else {
            try errW().print("unknown arg: {s}\n", .{arg});
            return error.Invalid;
        }
    }
    return null;
}

// -----------------------------------------------------------------------------
// Settings (file + CLI merge)
// -----------------------------------------------------------------------------

pub const Settings = struct {
    root: []const u8 = ".",
    port: u16 = 5173,
    open: bool = true, // CLI may flip this (e.g., preview default false)
    // Renderer-related toggles (passed through later):
    enable_katex: bool = true,
    enable_tailwind: bool = true,
    third_party_root: []const u8 = "third_party",
};

/// Minimal, stable JSON reader for a flat object:
/// Supports "root", "third_party_root" (strings),
/// "port" (int), "open", "enable_katex", "enable_tailwind" (bools).
pub fn loadSettings(alloc: std.mem.Allocator, path_opt: ?[]const u8) !Settings {
    var s: Settings = .{};
    const path = path_opt orelse "docz.settings.json";

    var f = std.fs.cwd().openFile(path, .{}) catch |e| {
        if (e == error.FileNotFound) return s; // defaults if missing
        return e;
    };
    defer f.close();

    const data = try f.readToEndAlloc(alloc, 1 << 16);
    defer alloc.free(data);

    // Strings
    if (findJsonStringValue(data, "root")) |v| s.root = try alloc.dupe(u8, v);
    if (findJsonStringValue(data, "third_party_root")) |v| s.third_party_root = try alloc.dupe(u8, v);
    // Ints
    if (findJsonIntValue(u16, data, "port")) |p| s.port = p;
    // Bools
    if (findJsonBoolValue(data, "open")) |b| s.open = b;
    if (findJsonBoolValue(data, "enable_katex")) |b| s.enable_katex = b;
    if (findJsonBoolValue(data, "enable_tailwind")) |b| s.enable_tailwind = b;

    return s;
}

/// Apply CLI overrides on top of file settings.
pub fn withCliOverrides(
    base: Settings,
    cli: struct {
        root: ?[]const u8 = null,
        port: ?u16 = null,
        no_open: bool = false,
        enable_katex: ?bool = null,
        enable_tailwind: ?bool = null,
        third_party_root: ?[]const u8 = null,
    },
) Settings {
    var out = base;
    if (cli.root) |r| out.root = r;
    if (cli.port) |p| out.port = p;
    if (cli.no_open) out.open = false;
    if (cli.enable_katex) |b| out.enable_katex = b;
    if (cli.enable_tailwind) |b| out.enable_tailwind = b;
    if (cli.third_party_root) |r| out.third_party_root = r;
    return out;
}

// -----------------------------------------------------------------------------
// Tiny JSON helpers (flat, tolerant, no escapes)
// -----------------------------------------------------------------------------

fn findJsonStringValue(buf: []const u8, key: []const u8) ?[]const u8 {
    var pat_buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&pat_buf);
    const A = fba.allocator();
    const quoted_key = std.fmt.allocPrint(A, "\"{s}\"", .{key}) catch return null;

    const key_i = std.mem.indexOf(u8, buf, quoted_key) orelse return null;

    var i: usize = key_i + quoted_key.len;
    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    if (i >= buf.len or buf[i] != ':') return null;
    i += 1; // after ':'

    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    if (i >= buf.len or buf[i] != '"') return null;
    i += 1; // start of value

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
    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    if (i >= buf.len or buf[i] != ':') return null;
    i += 1; // after ':'

    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
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
    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    if (i >= buf.len or buf[i] != ':') return null;
    i += 1; // after ':'

    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    if (i >= buf.len) return null;

    if (std.mem.startsWith(u8, buf[i..], "true")) return true;
    if (std.mem.startsWith(u8, buf[i..], "false")) return false;
    return null;
}

// ----------------------
// ✅ Tests (existing)
// ----------------------

test "common.detectKindFromPath: case-insensitive mapping" {
    try std.testing.expect(detectKindFromPath("x.dcz") == .dcz);
    try std.testing.expect(detectKindFromPath("x.DCZ") == .dcz);

    try std.testing.expect(detectKindFromPath("x.md") == .md);
    try std.testing.expect(detectKindFromPath("x.MD") == .md);

    try std.testing.expect(detectKindFromPath("x.html") == .html);
    try std.testing.expect(detectKindFromPath("x.htm") == .html);
    try std.testing.expect(detectKindFromPath("x.HTML") == .html);
    try std.testing.expect(detectKindFromPath("x.HTM") == .html);

    try std.testing.expect(detectKindFromPath("x.tex") == .tex);
    try std.testing.expect(detectKindFromPath("x.TEX") == .tex);

    try std.testing.expect(detectKindFromPath("x") == null);
    try std.testing.expect(detectKindFromPath("x.unknown") == null);
}
