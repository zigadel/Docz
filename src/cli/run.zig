const std = @import("std");
const docz = @import("docz");
const html_export = @import("html_export");
const common = @import("./common.zig");

// ─────────────────────────────────────────────────────────────
// Embedded core CSS (always linked first)
// ─────────────────────────────────────────────────────────────
const CORE_CSS_BYTES: []const u8 = docz.assets.core_css;
const CORE_CSS_NAME: []const u8 = "docz.core.css";
const TAILWIND_CSS_NAME: []const u8 = "docz.tailwind.css";

// --------- Live reload helpers (poll file) ---------

const LIVE_MARKER = "__docz_hot.txt";

fn writeHotMarker(alloc: std.mem.Allocator, out_dir: []const u8) !void {
    const path = try std.fs.path.join(alloc, &.{ out_dir, LIVE_MARKER });
    defer alloc.free(path);

    // Hash a timestamp to a u64 seed (portable across Zig versions)
    const t: i128 = std.time.nanoTimestamp();
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&t));
    const seed: u64 = hasher.final();

    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random().int(u64);

    const payload = try std.fmt.allocPrint(alloc, "{d}-{x}\n", .{ std.time.milliTimestamp(), r });
    defer alloc.free(payload);

    try common.writeFile(path, payload);
}

fn injectLiveScript(alloc: std.mem.Allocator, html: []const u8) ![]u8 {
    const script =
        \\<script>
        \\(function(){
        \\  var URL = "__DOCZ_HOT__";
        \\  var last = null;
        \\  function tick(){
        \\    fetch(URL, {cache: 'no-store'}).then(function(r){return r.text()}).then(function(t){
        \\      if (last === null) last = t;
        \\      else if (t !== last) location.reload();
        \\    }).catch(function(_){}).finally(function(){ setTimeout(tick, 500); });
        \\  }
        \\  tick();
        \\})();
        \\</script>
        \\
    ;

    const idx_opt = std.mem.indexOf(u8, html, "</body>");
    const tag = try std.fmt.allocPrint(alloc, "{s}", .{script});
    defer alloc.free(tag);

    const with_url = try std.mem.replaceOwned(u8, alloc, tag, "__DOCZ_HOT__", LIVE_MARKER);
    errdefer alloc.free(with_url);

    if (idx_opt) |idx| {
        var out = std.ArrayList(u8).init(alloc);
        errdefer out.deinit();
        try out.appendSlice(html[0..idx]);
        try out.appendSlice(with_url);
        try out.appendSlice(html[idx..]);
        return out.toOwnedSlice();
    }

    // Fallback: append at end if no </body>
    return std.fmt.allocPrint(alloc, "{s}\n{s}", .{ html, with_url });
}

const CssMode = enum { inline_css, file };

const GenerateOpts = struct { css_mode: CssMode = .inline_css, pretty: bool = true, live_reload: bool = true, css_file_name: []const u8 = "docz.css" };

fn insertCssLinkBeforeHeadClose(alloc: std.mem.Allocator, html: []const u8, href: []const u8) ![]u8 {
    const needle = "</head>";
    const idx_opt = std.mem.indexOf(u8, html, needle);
    if (idx_opt == null) {
        return try std.fmt.allocPrint(alloc, "<link rel=\"stylesheet\" href=\"{s}\">\n{s}", .{ href, html });
    }
    const idx = idx_opt.?;

    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    try out.appendSlice(html[0..idx]);
    try out.appendSlice("<link rel=\"stylesheet\" href=\"");
    try out.appendSlice(href);
    try out.appendSlice("\">\n");
    try out.appendSlice(html[idx..]);

    return out.toOwnedSlice();
}

// --- tiny pretty printer (unchanged logic) ---
fn prettyHtml(alloc: std.mem.Allocator, html: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    var indent: usize = 0;
    var i: usize = 0;

    while (i < html.len) {
        const line_start = i;
        while (i < html.len and html[i] != '\n') : (i += 1) {}
        const raw = html[line_start..i];
        if (i < html.len and html[i] == '\n') i += 1;

        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) {
            try out.append('\n');
            continue;
        }

        var j: usize = 0;
        while (j < line.len and (line[j] == ' ' or line[j] == '\t' or line[j] == '\r')) : (j += 1) {}
        const starts_with_lt = (j < line.len and line[j] == '<');

        var pre_decr: usize = 0;
        var post_incr: usize = 0;

        if (starts_with_lt) {
            const after_lt = j + 1;
            const is_close = after_lt < line.len and line[after_lt] == '/';
            const is_decl = after_lt < line.len and (line[after_lt] == '!' or line[after_lt] == '?');

            var name_start: usize = after_lt;
            if (is_close) name_start += 1;
            while (name_start < line.len and (line[name_start] == ' ' or line[name_start] == '\t' or line[name_start] == '\r')) : (name_start += 1) {}

            var name_end = name_start;
            while (name_end < line.len) : (name_end += 1) {
                const ch = line[name_end];
                if (ch == '>' or ch == '/' or ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n') break;
            }
            const tag_name = if (name_end > name_start) line[name_start..name_end] else line[name_start..name_start];

            const voidish = std.mem.eql(u8, tag_name, "meta") or
                std.mem.eql(u8, tag_name, "link") or
                std.mem.eql(u8, tag_name, "br") or
                std.mem.eql(u8, tag_name, "img") or
                std.mem.eql(u8, tag_name, "hr");
            const self_closed = line.len >= 2 and line[line.len - 2] == '/' and line[line.len - 1] == '>';
            const has_inline_close = std.mem.indexOf(u8, line, "</") != null;

            if (is_close and !is_decl) {
                if (indent > 0) pre_decr = 1;
            } else if (!is_decl and !self_closed and !voidish and !has_inline_close) {
                post_incr = 1;
            }
        }

        if (pre_decr > 0 and indent >= pre_decr) indent -= pre_decr;

        try out.appendNTimes(' ', indent * 2);
        try out.appendSlice(line);
        try out.append('\n');

        indent += post_incr;
    }

    return out.toOwnedSlice();
}

// ─────────────────────────────────────────────────────────────
// Tailwind discovery + copy into out_dir if present
// ─────────────────────────────────────────────────────────────

/// Return true if `cand` should replace `best_name` using a lexicographic tie-breaker.
/// We prefer the lexicographically *later* name (e.g., "2.1.0" beats "2.0.9").
/// If `have_best` is false, any candidate wins.
fn lexCandidateBeatsCurrent(have_best: bool, best_name: []const u8, cand: []const u8) bool {
    return (!have_best) or std.mem.lessThan(u8, best_name, cand);
}

/// Find the best Tailwind theme CSS on disk:
///   third_party/tailwind/<version>/css/docz.tailwind.css
/// Preference: newest by directory mtime; fall back to lexicographic order.
/// Returns an owned path slice (caller must `alloc.free`) or null if not found.
pub fn tailwindSourceCssPath(alloc: std.mem.Allocator) !?[]u8 {
    const family_dir = "third_party/tailwind";

    var fam = std.fs.cwd().openDir(family_dir, .{ .iterate = true }) catch |e| switch (e) {
        error.FileNotFound => return null,
        else => return e,
    };
    defer fam.close();

    var it = fam.iterate();

    var have_best = false;
    var best_name: []u8 = &[_]u8{};
    var best_mtime: i128 = 0;

    while (try it.next()) |ent| {
        if (ent.kind != .directory) continue;
        if (ent.name.len == 0 or ent.name[0] == '.') continue;

        const dir_abs = try std.fs.path.join(alloc, &.{ family_dir, ent.name });
        defer alloc.free(dir_abs);

        const css_abs = try std.fs.path.join(alloc, &.{ dir_abs, "css", "docz.tailwind.css" });
        defer alloc.free(css_abs);

        // access(): success => void; errors => error set. Convert to bool explicitly.
        const present = blk: {
            std.fs.cwd().access(css_abs, .{}) catch break :blk false;
            break :blk true;
        };
        if (!present) continue;

        // Prefer by mtime; if stat fails, use lexicographic tie-breaker.
        const st = std.fs.cwd().statFile(dir_abs) catch |e| switch (e) {
            error.FileNotFound, error.AccessDenied => {
                if (lexCandidateBeatsCurrent(have_best, best_name, ent.name)) {
                    if (have_best) alloc.free(best_name);
                    best_name = try alloc.dupe(u8, ent.name);
                    have_best = true;
                }
                continue;
            },
            else => return e,
        };

        const m = st.mtime;
        if (!have_best or m > best_mtime) {
            if (have_best) alloc.free(best_name);
            best_name = try alloc.dupe(u8, ent.name);
            best_mtime = m;
            have_best = true;
        }
    }

    if (!have_best) return null;

    const final_path = try std.fs.path.join(alloc, &.{ family_dir, best_name, "css", "docz.tailwind.css" });
    alloc.free(best_name);

    // Double-check presence
    const ok = blk: {
        std.fs.cwd().access(final_path, .{}) catch break :blk false;
        break :blk true;
    };
    if (!ok) {
        alloc.free(final_path);
        return null;
    }
    return final_path;
}

fn copyFileStreaming(src_abs: []const u8, dest_abs: []const u8) !void {
    if (std.fs.path.dirname(dest_abs)) |d| try std.fs.cwd().makePath(d);

    var in_file = try std.fs.cwd().openFile(src_abs, .{});
    defer in_file.close();

    var out_file = try std.fs.cwd().createFile(dest_abs, .{ .truncate = true });
    defer out_file.close();

    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try in_file.read(&buf);
        if (n == 0) break;
        try out_file.writeAll(buf[0..n]);
    }
}

// --------- generation (once) ---------

fn generateOnce(
    alloc: std.mem.Allocator,
    dcz_path: []const u8,
    out_dir: []const u8,
    opts: GenerateOpts,
) !void {
    const input = try common.readFileAlloc(alloc, dcz_path);
    defer alloc.free(input);

    const kind = common.detectKindFromPath(dcz_path) orelse return error.Unsupported;
    if (kind != .dcz) return error.ExpectedDcz;

    // DCZ -> AST
    const tokens = try docz.Tokenizer.tokenize(input, alloc);
    defer {
        docz.Tokenizer.freeTokens(alloc, tokens);
        alloc.free(tokens);
    }
    var ast = try docz.Parser.parse(tokens, alloc);
    defer ast.deinit();

    // HTML with inline <style>
    const html_inline = try html_export.exportHtml(&ast, alloc);
    errdefer alloc.free(html_inline);

    var final_html: []u8 = html_inline;

    // ── Core CSS: write and link FIRST
    {
        const core_out = try std.fs.path.join(alloc, &.{ out_dir, CORE_CSS_NAME });
        defer alloc.free(core_out);
        try common.writeFile(core_out, CORE_CSS_BYTES);

        const linked_core = try insertCssLinkBeforeHeadClose(alloc, final_html, CORE_CSS_NAME);
        alloc.free(final_html);
        final_html = linked_core;
    }

    // ── If exporting to an external stylesheet, write & link it SECOND (after core)
    if (opts.css_mode == .file) {
        const css_blob = try html_export.collectInlineCss(&ast, alloc);
        defer alloc.free(css_blob);

        const css_out = try std.fs.path.join(alloc, &.{ out_dir, opts.css_file_name });
        defer alloc.free(css_out);
        try common.writeFile(css_out, css_blob);

        // Strip inline <style> from HTML, then link external
        const no_style = try html_export.stripFirstStyleBlock(final_html, alloc);
        alloc.free(final_html);
        final_html = no_style;

        const linked = try insertCssLinkBeforeHeadClose(alloc, final_html, opts.css_file_name);
        alloc.free(final_html);
        final_html = linked;
    }

    // ── Tailwind (vendored) THIRD: copy to out_dir and link last if available
    if (try tailwindSourceCssPath(alloc)) |src_tw| {
        defer alloc.free(src_tw);
        const tw_out = try std.fs.path.join(alloc, &.{ out_dir, TAILWIND_CSS_NAME });
        defer alloc.free(tw_out);
        try copyFileStreaming(src_tw, tw_out);

        const linked_tw = try insertCssLinkBeforeHeadClose(alloc, final_html, TAILWIND_CSS_NAME);
        alloc.free(final_html);
        final_html = linked_tw;
    }

    if (opts.live_reload) {
        const with_live = try injectLiveScript(alloc, final_html);
        alloc.free(final_html);
        final_html = with_live;
    }

    if (opts.pretty) {
        const pretty = try prettyHtml(alloc, final_html);
        alloc.free(final_html);
        final_html = pretty;
    }

    const html_out = try std.fs.path.join(alloc, &.{ out_dir, "index.html" });
    defer alloc.free(html_out);

    try common.writeFile(html_out, final_html);
    alloc.free(final_html);

    // Update hot marker last (so the browser only reloads when the new HTML is fully written)
    if (opts.live_reload) try writeHotMarker(alloc, out_dir);
}

fn fileMTime(path: []const u8) !i128 {
    const st = try std.fs.cwd().statFile(path);
    return st.mtime;
}

fn spawnPreview(alloc: std.mem.Allocator, root_dir: []const u8, port: u16) !std.process.Child {
    const exe_path = try std.fs.selfExePathAlloc(alloc);
    defer alloc.free(exe_path);

    var argv = std.ArrayList([]const u8).init(alloc);
    errdefer argv.deinit();

    try argv.append(exe_path);
    try argv.append("preview");
    try argv.append("--root");
    try argv.append(root_dir);
    try argv.append("--port");
    const port_str = try std.fmt.allocPrint(alloc, "{}", .{port});
    defer alloc.free(port_str);
    try argv.append(port_str);
    // prevent preview from opening its own tab (run opens the correct one)
    try argv.append("--no-open");

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
    // If config exists by default, load it (we only use the port here)
    settings = common.loadSettings(alloc, null) catch settings;

    var port: u16 = settings.port; // defaults to 5173 if no config

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
    var last = try fileMTime(dcz_path);
    while (true) {
        std.Thread.sleep(250 * std.time.ns_per_ms);

        const now = fileMTime(dcz_path) catch continue;
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
