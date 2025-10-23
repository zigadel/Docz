const std = @import("std");

// Insert a <link rel="stylesheet" href="..."> before </head>
// (or prefix the document if no </head> exists).
pub fn insertCssLinkBeforeHeadClose(
    alloc: std.mem.Allocator,
    html: []const u8,
    href: []const u8,
) ![]u8 {
    const needle = "</head>";
    const idx_opt = std.mem.indexOf(u8, html, needle);
    if (idx_opt == null) {
        return try std.fmt.allocPrint(alloc, "<link rel=\"stylesheet\" href=\"{s}\">\n{s}", .{ href, html });
    }
    const idx = idx_opt.?;

    var out = std.ArrayList(u8){};
    errdefer out.deinit(alloc);

    try out.appendSlice(alloc, html[0..idx]);
    try out.appendSlice(alloc, "<link rel=\"stylesheet\" href=\"");
    try out.appendSlice(alloc, href);
    try out.appendSlice(alloc, "\">\n");
    try out.appendSlice(alloc, html[idx..]);

    return out.toOwnedSlice(alloc);
}

pub fn insertBeforeHeadClose(
    alloc: std.mem.Allocator,
    html: []const u8,
    snippet: []const u8,
) ![]u8 {
    const needle = "</head>";
    if (std.mem.indexOf(u8, html, needle)) |idx| {
        var out = std.ArrayList(u8){};
        errdefer out.deinit(alloc);
        try out.appendSlice(alloc, html[0..idx]);
        try out.appendSlice(alloc, snippet);
        try out.appendSlice(alloc, html[idx..]);
        return out.toOwnedSlice(alloc);
    }
    return std.fmt.allocPrint(alloc, "{s}{s}", .{ snippet, html });
}

// Hot-reload marker + script
pub fn writeHotMarker(alloc: std.mem.Allocator, out_dir: []const u8, marker_name: []const u8) !void {
    const path = try std.fs.path.join(alloc, &.{ out_dir, marker_name });
    defer alloc.free(path);

    const t: i128 = std.time.nanoTimestamp();
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&t));
    const seed: u64 = hasher.final();

    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random().int(u64);

    const payload = try std.fmt.allocPrint(alloc, "{d}-{x}\n", .{ std.time.milliTimestamp(), r });
    defer alloc.free(payload);

    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(payload);
}

pub fn injectLiveScript(alloc: std.mem.Allocator, html: []const u8, marker_name: []const u8) ![]u8 {
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

    const with_url = try std.mem.replaceOwned(u8, alloc, tag, "__DOCZ_HOT__", marker_name);
    errdefer alloc.free(with_url);

    if (idx_opt) |idx| {
        var out = std.ArrayList(u8){};
        errdefer out.deinit(alloc);
        try out.appendSlice(alloc, html[0..idx]);
        try out.appendSlice(alloc, with_url);
        try out.appendSlice(alloc, html[idx..]);
        return out.toOwnedSlice(alloc);
    }

    // Fallback: append at end if no </body>
    return std.fmt.allocPrint(alloc, "{s}\n{s}", .{ html, with_url });
}

// Lightweight pretty printer for readability in dev
pub fn prettyHtml(alloc: std.mem.Allocator, html: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(alloc);

    var indent: usize = 0;
    var i: usize = 0;

    while (i < html.len) {
        const line_start = i;
        while (i < html.len and html[i] != '\n') : (i += 1) {}
        const raw = html[line_start..i];
        if (i < html.len and html[i] == '\n') i += 1;

        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) {
            try out.append(alloc, '\n');
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

            const voidish =
                std.mem.eql(u8, tag_name, "meta") or
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

        try out.appendNTimes(alloc, ' ', indent * 2);
        try out.appendSlice(alloc, line);
        try out.append(alloc, '\n');

        indent += post_incr;
    }

    return out.toOwnedSlice(alloc);
}
