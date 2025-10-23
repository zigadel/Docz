const std = @import("std");
const ASTNode = @import("../parser/ast.zig").ASTNode;
const NodeType = @import("../parser/ast.zig").NodeType;

// -----------------------------------------------------------------------------
// Small writer adapter for ArrayList(u8) on this Zig version
// (Avoids std.ArrayList.writer() and std.io.Writer differences between builds.)
// -----------------------------------------------------------------------------
const ListWriter = struct {
    list: *std.ArrayList(u8),
    alloc: std.mem.Allocator,

    fn writeAll(self: *const ListWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.alloc, bytes);
    }

    fn print(self: *const ListWriter, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.alloc, fmt, args);
        defer self.alloc.free(s);
        try self.list.appendSlice(self.alloc, s);
    }
};

// -----------------------------------------------------------------------------
// Asset options + VENDOR.lock reader
// -----------------------------------------------------------------------------

pub const RenderAssets = struct {
    enable_katex: bool = true,
    enable_tailwind: bool = true,
    third_party_root: []const u8 = "third_party",
};

fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    return std.fs.cwd().readFileAlloc(path, alloc, @enumFromInt(max));
}

/// Very small JSON helper: find string value for a top-level key, assuming
/// a simple object like: {"katex":"0.16.11","tailwind":"docz-theme-1.0.0"}
/// This intentionally avoids std.json for stability across Zig versions.
fn findJsonStringValue(buf: []const u8, key: []const u8) ?[]const u8 {
    // Look for "key"
    var pat_buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&pat_buf);
    const A = fba.allocator();
    const quoted_key = std.fmt.allocPrint(A, "\"{s}\"", .{key}) catch return null;

    const key_i = std.mem.indexOf(u8, buf, quoted_key) orelse return null;

    // Find colon after key
    var i: usize = key_i + quoted_key.len;
    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    if (i >= buf.len or buf[i] != ':') return null;
    i += 1;

    // Find opening quote of the value
    while (i < buf.len and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\r' or buf[i] == '\n')) : (i += 1) {}
    if (i >= buf.len or buf[i] != '"') return null;
    i += 1; // start of value

    const start = i;
    // Find closing quote (no escape handling needed for plain versions/labels)
    while (i < buf.len and buf[i] != '"') : (i += 1) {}
    if (i >= buf.len) return null;

    return buf[start..i];
}

fn readVendorLock(alloc: std.mem.Allocator, third_party_root: []const u8) !struct {
    katex: ?[]const u8,
    tailwind: ?[]const u8,
} {
    const lock_path = try std.fs.path.join(alloc, &.{ third_party_root, "VENDOR.lock" });
    defer alloc.free(lock_path);

    const buf = readFileAlloc(alloc, lock_path, 1 << 16) catch |e| {
        if (e == error.FileNotFound) return .{ .katex = null, .tailwind = null };
        return e;
    };
    defer alloc.free(buf);

    const k = findJsonStringValue(buf, "katex");
    const t = findJsonStringValue(buf, "tailwind");

    return .{
        .katex = if (k) |s| try alloc.dupe(u8, s) else null,
        .tailwind = if (t) |s| try alloc.dupe(u8, s) else null,
    };
}

/// Emit <link>/<script> tags for vendored assets based on VENDOR.lock.
pub fn emitHeadAssets(alloc: std.mem.Allocator, w: anytype, opts: RenderAssets) !void {
    const lock = try readVendorLock(alloc, opts.third_party_root);
    defer if (lock.katex) |s| alloc.free(s);
    defer if (lock.tailwind) |s| alloc.free(s);

    if (opts.enable_tailwind) {
        if (lock.tailwind) |ver| {
            try w.print(
                "<link rel=\"stylesheet\" href=\"/third_party/tailwind/docz-theme-{s}/css/docz.tailwind.css\"/>\n",
                .{ver},
            );
        }
    }
    if (opts.enable_katex) {
        if (lock.katex) |ver| {
            try w.print(
                \\<link rel="stylesheet" href="/third_party/katex/{s}/dist/katex.min.css"/>
                \\<script defer src="/third_party/katex/{s}/dist/katex.min.js"></script>
                \\
            , .{ ver, ver });
        }
    }
}

// -----------------------------------------------------------------------------
// Existing helpers (kept)
// -----------------------------------------------------------------------------

fn lessStr(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn styleKeyPriority(k: []const u8) u8 {
    if (std.mem.eql(u8, k, "font-size")) return 0; // ensure font-size first
    if (std.mem.eql(u8, k, "color")) return 1; // then color
    return 100; // others later
}

fn styleKeyLess(_: void, a: []const u8, b: []const u8) bool {
    const pa = styleKeyPriority(a);
    const pb = styleKeyPriority(b);
    if (pa != pb) return pa < pb; // priority first
    return std.mem.lessThan(u8, a, b); // then lexicographic
}

/// Converts attributes → inline CSS string; excludes non-style keys (like "mode")
fn buildInlineStyle(attributes: std.StringHashMap([]const u8), allocator: std.mem.Allocator) ![]u8 {
    var keys = std.ArrayList([]const u8){};
    defer keys.deinit(allocator);

    var it = attributes.iterator();
    while (it.next()) |entry| {
        const k = entry.key_ptr.*;
        if (std.mem.eql(u8, k, "mode")) continue; // exclude control key
        try keys.append(allocator, k);
    }

    // sort with priority
    std.mem.sort([]const u8, keys.items, {}, styleKeyLess);

    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    var lw = ListWriter{ .list = &out, .alloc = allocator };

    var first = true;
    for (keys.items) |k| {
        const v = attributes.get(k).?;
        if (!first) try lw.print(";", .{});
        try lw.print("{s}:{s}", .{ k, v });
        first = false;
    }
    try lw.print(";", .{}); // trailing ; expected by the test

    return try out.toOwnedSlice(allocator);
}

/// Converts style-def content into CSS
fn buildGlobalCSS(styleContent: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var builder = std.ArrayList(u8){};
    defer builder.deinit(allocator);
    var lw = ListWriter{ .list = &builder, .alloc = allocator };

    var lines = std.mem.tokenizeScalar(u8, styleContent, '\n');
    while (lines.next()) |line| {
        var trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        const colonIndex = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
        const className = std.mem.trim(u8, trimmed[0..colonIndex], " \t");
        const propsRaw = std.mem.trim(u8, trimmed[colonIndex + 1 ..], " \t");

        try lw.print(".{s} {{ ", .{className});

        var propsIter = std.mem.tokenizeScalar(u8, propsRaw, ',');
        var first = true;
        while (propsIter.next()) |prop| {
            var cleanProp = std.mem.trim(u8, prop, " \t");
            const eqIndex = std.mem.indexOfScalar(u8, cleanProp, '=') orelse continue;
            const key = std.mem.trim(u8, cleanProp[0..eqIndex], " \t");
            const value = std.mem.trim(u8, cleanProp[eqIndex + 1 ..], " \t\"");

            if (!first) try lw.print(" ", .{});
            try lw.print("{s}:{s};", .{ key, value });
            first = false;
        }

        try lw.print(" }}\n", .{});
    }

    return try builder.toOwnedSlice(allocator);
}

// -----------------------------------------------------------------------------
// Renderer
// -----------------------------------------------------------------------------

pub fn renderHTML(root: *const ASTNode, allocator: std.mem.Allocator) ![]u8 {
    var list = std.ArrayList(u8){};
    var w = ListWriter{ .list = &list, .alloc = allocator };

    try w.print("<!DOCTYPE html>\n<html>\n<head>\n", .{});

    // Meta information
    for (root.children.items) |node| {
        if (node.node_type == .Meta) {
            var it = node.attributes.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, "title")) {
                    try w.print("<title>{s}</title>\n", .{entry.value_ptr.*});
                } else {
                    try w.print("<meta name=\"{s}\" content=\"{s}\">\n", .{
                        entry.key_ptr.*, entry.value_ptr.*,
                    });
                }
            }
        }
    }

    // Global CSS (from Style nodes in "global" mode)
    var globalCSSBuilder = std.ArrayList(u8){};
    var gw = ListWriter{ .list = &globalCSSBuilder, .alloc = allocator };

    for (root.children.items) |node| {
        if (node.node_type == .Style) {
            if (node.attributes.get("mode")) |mode| {
                if (std.mem.eql(u8, mode, "global")) {
                    const css = try buildGlobalCSS(node.content, allocator);
                    defer allocator.free(css);
                    try gw.print("{s}\n", .{css});
                }
            }
        }
    }

    if (globalCSSBuilder.items.len > 0) {
        try w.print("<style>\n{s}</style>\n", .{globalCSSBuilder.items});
    }
    globalCSSBuilder.deinit(allocator);

    // Vendored assets (Tailwind / KaTeX), read from VENDOR.lock if present.
    try emitHeadAssets(allocator, w, .{});

    try w.print("</head>\n<body>\n", .{});

    // Body rendering
    for (root.children.items) |node| {
        switch (node.node_type) {
            .Meta => {
                // Meta already emitted into <head>; skip in body to avoid noise.
            },
            .Heading => {
                const level = node.attributes.get("level") orelse "1";
                const text = std.mem.trimRight(u8, node.content, " \t\r\n");
                try w.print("<h{s}>{s}</h{s}>\n", .{ level, text, level });
            },
            .Content => {
                try w.print("<p>{s}</p>\n", .{node.content});
            },
            .CodeBlock => {
                try w.print("<pre><code>{s}</code></pre>\n", .{node.content});
            },
            .Math => {
                try w.print("<div class=\"math\">{s}</div>\n", .{node.content});
            },
            .Media => {
                const src = node.attributes.get("src") orelse "";
                try w.print("<img src=\"{s}\" />\n", .{src});
            },
            .Import => {
                const path = node.attributes.get("href") orelse "";
                try w.print("<link rel=\"stylesheet\" href=\"{s}\">\n", .{path});
            },
            .Style => {
                if (node.attributes.get("mode")) |mode| {
                    if (std.mem.eql(u8, mode, "inline")) {
                        const inlineCSS = try buildInlineStyle(node.attributes, allocator);
                        defer allocator.free(inlineCSS);
                        try w.print("<span style=\"{s}\">{s}</span>\n", .{ inlineCSS, node.content });
                    }
                }
            },
            else => {
                try w.print("<!-- Unhandled node: {s} -->\n", .{@tagName(node.node_type)});
            },
        }
    }

    try w.print("</body>\n</html>\n", .{});
    return try list.toOwnedSlice(allocator);
}

// ----------------------
// ✅ Tests
// ----------------------

test "Render HTML with inline style" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var root = ASTNode.init(allocator, NodeType.Document);
    defer root.deinit(allocator);

    var styleNode = ASTNode.init(allocator, NodeType.Style);
    try styleNode.attributes.put("mode", "inline");
    try styleNode.attributes.put("font-size", "18px");
    try styleNode.attributes.put("color", "blue");
    styleNode.content = "Styled Text";
    try root.children.append(allocator, styleNode);

    const html = try renderHTML(&root, allocator);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "style=\"font-size:18px;color:blue;\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Styled Text") != null);
}

test "Render HTML with global style-def" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var root = ASTNode.init(allocator, NodeType.Document);
    defer root.deinit(allocator);

    var globalStyleNode = ASTNode.init(allocator, NodeType.Style);
    // Zig 0.16 StringHashMap.put takes (key, value)
    try globalStyleNode.attributes.put("mode", "global");
    globalStyleNode.content =
        \\heading-level-1: font-size=36px, font-weight=bold
        \\body-text: font-family="Inter", line-height=1.6
    ;
    try root.children.append(allocator, globalStyleNode);

    const html = try renderHTML(&root, allocator);
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, ".heading-level-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, ".body-text") != null);
}
