const std = @import("std");
const docz = @import("docz");

const html_export = @import("html_export");
// (md/html/tex import/export are available elsewhere; not needed here)

const Kind = enum { dcz, md, html, tex };

fn detectKindFromPath(p: []const u8) ?Kind {
    const ext = std.fs.path.extension(p);
    if (ext.len == 0) return null;
    if (std.ascii.eqlIgnoreCase(ext, ".dcz")) return .dcz;
    if (std.ascii.eqlIgnoreCase(ext, ".md")) return .md;
    if (std.ascii.eqlIgnoreCase(ext, ".html") or std.ascii.eqlIgnoreCase(ext, ".htm")) return .html;
    if (std.ascii.eqlIgnoreCase(ext, ".tex")) return .tex;
    return null;
}

fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    return try f.readToEndAlloc(alloc, 1 << 26);
}

fn writeFile(path: []const u8, data: []const u8) !void {
    const cwd = std.fs.cwd();
    if (std.fs.path.dirname(path)) |dirpart| {
        try cwd.makePath(dirpart);
    }
    var f = try cwd.createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}

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

// --- tiny pretty printer (unchanged) ---
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

// --------- Live reload helpers (poll file) ---------

const LIVE_MARKER = "__docz_hot.txt";

fn writeHotMarker(alloc: std.mem.Allocator, out_dir: []const u8) !void {
    const path = try std.fs.path.join(alloc, &.{ out_dir, LIVE_MARKER });
    defer alloc.free(path);

    // Hash the i128 timestamp to a u64 seed (portable across Zig versions)
    const t: i128 = std.time.nanoTimestamp();
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&t));
    const seed: u64 = hasher.final();

    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random().int(u64);

    const payload = try std.fmt.allocPrint(alloc, "{d}-{x}\n", .{ std.time.milliTimestamp(), r });
    defer alloc.free(payload);

    try writeFile(path, payload);
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

const GenerateOpts = struct {
    css_mode: CssMode = .inline_css,
    pretty: bool = true,
    live_reload: bool = true,
    css_file_name: []const u8 = "docz.css",
};

fn generateOnce(
    alloc: std.mem.Allocator,
    dcz_path: []const u8,
    out_dir: []const u8,
    opts: GenerateOpts,
) !void {
    const input = try readFileAlloc(alloc, dcz_path);
    defer alloc.free(input);

    const kind = detectKindFromPath(dcz_path) orelse return error.Unsupported;
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

    if (opts.css_mode == .file) {
        const css_blob = try html_export.collectInlineCss(&ast, alloc);
        defer alloc.free(css_blob);

        const css_out = try std.fs.path.join(alloc, &.{ out_dir, opts.css_file_name });
        defer alloc.free(css_out);
        try writeFile(css_out, css_blob);

        const no_style = try html_export.stripFirstStyleBlock(final_html, alloc);
        alloc.free(final_html);
        final_html = no_style;

        const linked = try insertCssLinkBeforeHeadClose(alloc, final_html, opts.css_file_name);
        alloc.free(final_html);
        final_html = linked;
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

    try writeFile(html_out, final_html);
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

pub fn run(alloc: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const usage =
        \\Usage: docz run <path.dcz> [--port <num>] [--css inline|file] [--no-pretty] [--no-live]
        \\Notes:
        \\  - Compiles to a temp dir and serves it via `docz preview`
        \\  - Rebuilds + auto-reloads the browser when the .dcz changes
        \\
    ;

    const dcz_path = it.next() orelse {
        std.debug.print("{s}", .{usage});
        return error.Invalid;
    };

    var port: u16 = 5173;
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
