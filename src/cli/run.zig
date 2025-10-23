const std = @import("std");
const docz = @import("docz");
const common = @import("./common.zig");

const assets = @import("./assets.zig");
const html_ops = @import("./html_ops.zig");
const fallback = @import("./fallback.zig");

// ─────────────────────────────────────────────────────────────
// Embedded core CSS (shipped with Docz)
// ─────────────────────────────────────────────────────────────
const CORE_CSS_BYTES: []const u8 = docz.assets.core_css;
const CORE_CSS_NAME: []const u8 = "docz.core.css";
const TAILWIND_CSS_NAME: []const u8 = "docz.tailwind.css";

// ───────── Live reload marker name ─────────
const LIVE_MARKER = "__docz_hot.txt";

const CssMode = enum { inline_css, file };

const GenerateOpts = struct {
    css_mode: CssMode = .inline_css,
    pretty: bool = true,
    live_reload: bool = true,
    css_file_name: []const u8 = "docz.css",
};

// ─────────────────────────────────────────────────────────────
// Preview helpers (spawn/open)
// ─────────────────────────────────────────────────────────────

fn spawnPreview(alloc: std.mem.Allocator, root_dir: []const u8, port: u16) !std.process.Child {
    const exe_path = try std.fs.selfExePathAlloc(alloc);
    defer alloc.free(exe_path);

    var argv = std.ArrayList([]const u8){};
    errdefer argv.deinit(alloc);

    try argv.append(alloc, exe_path);
    try argv.append(alloc, "preview");
    try argv.append(alloc, "--root");
    try argv.append(alloc, root_dir);
    try argv.append(alloc, "--port");
    const port_str = try std.fmt.allocPrint(alloc, "{}", .{port});
    defer alloc.free(port_str);
    try argv.append(alloc, port_str);
    try argv.append(alloc, "--no-open"); // run opens the browser

    var child = std.process.Child.init(argv.items, alloc);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    try child.spawn();

    return child;
}

fn openBrowserToIndex(alloc: std.mem.Allocator, port: u16) !void {
    const url = try std.fmt.allocPrint(alloc, "http://127.0.0.1:{d}/index.html", .{port});
    defer alloc.free(url);

    const os = @import("builtin").os.tag;
    const argv = switch (os) {
        .windows => &[_][]const u8{ "cmd", "/c", "start", url },
        .macos => &[_][]const u8{ "open", url },
        else => &[_][]const u8{ "xdg-open", url },
    };

    var child = std.process.Child.init(argv, alloc);
    _ = child.spawn() catch {};
}

// ─────────────────────────────────────────────────────────────
// One-shot generate to .zig-cache/docz-run
// ─────────────────────────────────────────────────────────────

fn generateOnce(
    alloc: std.mem.Allocator,
    dcz_path: []const u8,
    out_dir: []const u8,
    opts: GenerateOpts,
) !void {
    // 0) Read input and render a full HTML document (<head> + <body>)
    const input = try common.readFileAlloc(alloc, dcz_path);
    defer alloc.free(input);

    var final_html = try fallback.render(alloc, input);
    defer alloc.free(final_html);

    // 1) Core CSS — write file and link FIRST
    {
        const core_out = try std.fs.path.join(alloc, &.{ out_dir, CORE_CSS_NAME });
        defer alloc.free(core_out);
        try common.writeFile(core_out, CORE_CSS_BYTES);

        const linked_core = try html_ops.insertCssLinkBeforeHeadClose(alloc, final_html, CORE_CSS_NAME);
        alloc.free(final_html);
        final_html = linked_core;
    }

    // 2) Optional external CSS (empty/stub or user-provided path name)
    if (opts.css_mode == .file) {
        const css_out = try std.fs.path.join(alloc, &.{ out_dir, opts.css_file_name });
        defer alloc.free(css_out);
        // Write an empty file if caller didn't already generate one upstream.
        try common.writeFile(css_out, "");

        const linked = try html_ops.insertCssLinkBeforeHeadClose(alloc, final_html, opts.css_file_name);
        alloc.free(final_html);
        final_html = linked;
    }

    // 3) Tailwind (vendored or monorepo build) — link LAST among CSS if discovered
    if (assets.findTailwindCss(alloc) catch null) |src_tw| {
        defer alloc.free(src_tw);

        const tw_out = try std.fs.path.join(alloc, &.{ out_dir, TAILWIND_CSS_NAME });
        defer alloc.free(tw_out);
        try assets.copyFileStreaming(src_tw, tw_out);

        const linked_tw = try html_ops.insertCssLinkBeforeHeadClose(alloc, final_html, TAILWIND_CSS_NAME);
        alloc.free(final_html);
        final_html = linked_tw;
    }

    // 4) KaTeX (vendored) — inject assets + init script if available
    if (assets.findKatexAssets(alloc) catch null) |k| {
        defer {
            alloc.free(k.css_href);
            alloc.free(k.js_href);
            alloc.free(k.auto_href);
        }

        var sn = std.ArrayList(u8){};
        errdefer sn.deinit(alloc);

        // <link rel="stylesheet" href="...katex.min.css">
        try sn.appendSlice(alloc, "<link rel=\"stylesheet\" href=\"");
        try sn.appendSlice(alloc, k.css_href);
        try sn.appendSlice(alloc, "\">\n");

        // <script defer src="...katex.min.js"></script>
        try sn.appendSlice(alloc, "<script defer src=\"");
        try sn.appendSlice(alloc, k.js_href);
        try sn.appendSlice(alloc, "\"></script>\n");

        // <script defer src="...auto-render.min.js"></script>
        try sn.appendSlice(alloc, "<script defer src=\"");
        try sn.appendSlice(alloc, k.auto_href);
        try sn.appendSlice(alloc, "\"></script>\n");

        // Inline init (trust: true so \htmlClass/\htmlId/\htmlStyle/\htmlData work)
        // + gentle strictness and throwOnError:false for authoring friendliness.
        // Also add a convenience macro \class → \htmlClass for nicer authoring.
        try sn.appendSlice(alloc,
            \\<script>
            \\document.addEventListener('DOMContentLoaded', function () {
            \\  if (!window.renderMathInElement) return;
            \\  renderMathInElement(document.body, {
            \\    delimiters: [
            \\      {left: "$$", right: "$$", display: true},
            \\      {left: "$",  right: "$",  display: false},
            \\      {left: "\\(", right: "\\)", display: false},
            \\      {left: "\\[", right: "\\]", display: true}
            \\    ],
            \\    throwOnError: false,
            \\    strict: "ignore",
            \\    trust: true,
            \\    macros: {
            \\      "\\\\class": "\\\\htmlClass"
            \\    }
            \\  });
            \\});
            \\</script>
            \\
        );

        const snippet = try sn.toOwnedSlice(alloc);
        const injected = try html_ops.insertBeforeHeadClose(alloc, final_html, snippet);
        alloc.free(final_html);
        final_html = injected;
        alloc.free(snippet);
    }

    // 5) Live reload (dev) — small script + hot marker file
    if (opts.live_reload) {
        const with_live = try html_ops.injectLiveScript(alloc, final_html, LIVE_MARKER);
        alloc.free(final_html);
        final_html = with_live;
    }

    // 6) Pretty print (optional, cheap)
    if (opts.pretty) {
        const pretty = try html_ops.prettyHtml(alloc, final_html);
        alloc.free(final_html);
        final_html = pretty;
    }

    // 7) Write HTML and update hot marker last (after file is fully written)
    const html_out = try std.fs.path.join(alloc, &.{ out_dir, "index.html" });
    defer alloc.free(html_out);
    try common.writeFile(html_out, final_html);

    if (opts.live_reload) try html_ops.writeHotMarker(alloc, out_dir, LIVE_MARKER);
}

// -----------------------------------------------------------------------------
// CLI
// -----------------------------------------------------------------------------

pub fn run(alloc: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const usage =
        \\Usage: docz run <path.dcz> [--port <num>] [--css inline|file] [--no-pretty] [--no-live] [--config <file>]
        \\Notes:
        \\  - Compiles to a temp dir and serves it via `docz preview`
        \\  - Rebuilds + auto-reloads the browser when the .dcz changes
        \\
    ;

    const dcz_path = it.next() orelse {
        std.debug.print("{s}", .{usage});
        return error.Invalid;
    };

    // Defaults, optionally from config file
    var cfg_path: ?[]const u8 = null;
    var port_overridden = false;

    var settings = common.Settings{}; // defaults
    settings = common.loadSettings(alloc, null) catch settings;

    var port: u16 = settings.port;

    var css_mode: CssMode = .inline_css;
    var pretty: bool = true;
    var live_reload: bool = true;

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--port")) {
            const v = it.next() orelse {
                std.debug.print("run: --port requires a value\n", .{});
                return error.Invalid;
            };
            port = std.fmt.parseInt(u16, v, 10) catch {
                std.debug.print("run: invalid port: {s}\n", .{v});
                return error.Invalid;
            };
            port_overridden = true;
        } else if (std.mem.eql(u8, arg, "--css")) {
            const v = it.next() orelse {
                std.debug.print("run: --css requires a value: inline|file\n", .{});
                return error.Invalid;
            };
            if (std.mem.eql(u8, v, "inline")) css_mode = .inline_css else if (std.mem.eql(u8, v, "file")) css_mode = .file else {
                std.debug.print("run: --css must be 'inline' or 'file' (got '{s}')\n", .{v});
                return error.Invalid;
            }
        } else if (std.mem.eql(u8, arg, "--no-pretty")) {
            pretty = false;
        } else if (std.mem.eql(u8, arg, "--no-live")) {
            live_reload = false;
        } else if (std.mem.eql(u8, arg, "--config")) {
            const v = it.next() orelse {
                std.debug.print("run: --config requires a value\n", .{});
                return error.Invalid;
            };
            cfg_path = v;
            const s2 = common.loadSettings(alloc, cfg_path) catch settings;
            settings = s2;
            if (!port_overridden) port = settings.port;
        } else {
            std.debug.print("run: unknown arg: {s}\n", .{arg});
            return error.Invalid;
        }
    }

    // temp out dir inside zig-cache (portable & disposable)
    const tmp_root = try std.fs.path.join(alloc, &.{ ".zig-cache", "docz-run" });
    defer alloc.free(tmp_root);
    try std.fs.cwd().makePath(tmp_root);

    // initial build
    try generateOnce(alloc, dcz_path, tmp_root, .{
        .css_mode = css_mode,
        .pretty = pretty,
        .live_reload = live_reload,
    });

    // start preview server
    var preview = try spawnPreview(alloc, tmp_root, port);
    defer {
        _ = preview.kill() catch {};
        _ = preview.wait() catch {};
    }

    // open browser directly to the compiled HTML
    openBrowserToIndex(alloc, port) catch {};

    std.debug.print(
        "Serving on http://127.0.0.1:{d}  (dir: {s})  [live={any}]\n",
        .{ port, tmp_root, live_reload },
    );

    // watch loop (poll .dcz mtime)
    var last = try assets.fileMTime(dcz_path);
    while (true) {
        std.Thread.sleep(250 * std.time.ns_per_ms);

        const now = assets.fileMTime(dcz_path) catch continue;
        if (now != last) {
            last = now;
            generateOnce(alloc, dcz_path, tmp_root, .{
                .css_mode = css_mode,
                .pretty = pretty,
                .live_reload = live_reload,
            }) catch |e| {
                std.debug.print("run: rebuild failed: {s}\n", .{@errorName(e)});
            };
        }
    }
}
