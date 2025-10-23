const std = @import("std");

pub const NodeType = enum {
    Document,
    Meta,
    Heading,
    Content,
    CodeBlock,
    Math,
    Media,
    Import,
    Style, // semantic style application: @style(name) ... @end
    Css, // raw CSS block: @css() ... @end
    StyleDef, // semantic alias definitions: @style-def() ... @end
    Unknown, // future-proofing: retain unknown directives losslessly
};

pub const ASTNode = struct {
    node_type: NodeType,
    content: []const u8 = "",
    owns_content: bool = false,
    allocator: ?std.mem.Allocator = null,
    attributes: std.StringHashMap([]const u8),
    children: std.ArrayList(ASTNode),

    pub fn init(allocator: std.mem.Allocator, node_type: NodeType) ASTNode {
        return ASTNode{
            .node_type = node_type,
            .content = "",
            .owns_content = false,
            .allocator = allocator,
            .attributes = std.StringHashMap([]const u8).init(allocator),
            .children = std.ArrayList(ASTNode){},
        };
    }

    pub fn deinit(self: *ASTNode, alloc: std.mem.Allocator) void {
        // children first
        var i: usize = 0;
        while (i < self.children.items.len) : (i += 1) {
            self.children.items[i].deinit(alloc);
        }
        self.children.deinit(alloc);
        self.attributes.deinit();

        if (self.owns_content and self.content.len > 0) {
            if (self.allocator) |a| a.free(self.content);
        }
        self.content = "";
        self.owns_content = false;
    }

    pub fn addChild(self: *ASTNode, alloc: std.mem.Allocator, child: ASTNode) !void {
        try self.children.append(alloc, child);
    }

    pub fn setContentBorrowed(self: *ASTNode, slice: []const u8) void {
        if (self.owns_content and self.content.len > 0) {
            if (self.allocator) |a| a.free(self.content);
        }
        self.content = slice;
        self.owns_content = false;
    }

    pub fn setContentOwned(self: *ASTNode, allocator: std.mem.Allocator, slice: []const u8) !void {
        if (self.owns_content and self.content.len > 0) {
            if (self.allocator) |a| a.free(self.content);
        }
        const dup = try allocator.dupe(u8, slice);
        self.content = dup;
        self.owns_content = true;
        self.allocator = allocator;
    }

    pub fn addAttr(self: *ASTNode, key: []const u8, value: []const u8) !void {
        try self.attributes.put(key, value);
    }

    pub fn getAttr(self: *const ASTNode, key: []const u8) ?[]const u8 {
        if (self.attributes.get(key)) |v| return v;
        return null;
    }

    pub fn isBlockLike(self: *const ASTNode) bool {
        return switch (self.node_type) {
            .CodeBlock, .Math, .Style, .Css, .StyleDef => true,
            else => false,
        };
    }

    pub fn isHeadAsset(self: *const ASTNode) bool {
        return switch (self.node_type) {
            .Import, .Css, .Meta => true,
            else => false,
        };
    }

    pub fn cloneDeep(self: *const ASTNode, allocator: std.mem.Allocator) !ASTNode {
        var out = ASTNode.init(allocator, self.node_type);
        if (self.content.len > 0) {
            try out.setContentOwned(allocator, self.content);
        }
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            const k = try allocator.dupe(u8, entry.key_ptr.*);
            const v = try allocator.dupe(u8, entry.value_ptr.*);
            try out.attributes.put(k, v);
        }
        for (self.children.items) |child| {
            const dup_child = try child.cloneDeep(allocator);
            try out.children.append(allocator, dup_child);
        }
        return out;
    }

    pub fn parseStyleAliases(self: *const ASTNode, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
        var map = std.StringHashMap([]const u8).init(allocator);
        errdefer {
            var it_free = map.iterator();
            while (it_free.next()) |e| {
                allocator.free(e.key_ptr.*);
                allocator.free(e.value_ptr.*);
            }
            map.deinit();
        }

        if (self.node_type != .StyleDef or self.content.len == 0) {
            return map;
        }

        var it = std.mem.splitScalar(u8, self.content, '\n');
        while (it.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

            const colon_idx_opt = std.mem.indexOfScalar(u8, line, ':');
            if (colon_idx_opt == null) continue;
            const colon_idx = colon_idx_opt.?;

            const alias_trim = std.mem.trim(u8, line[0..colon_idx], " \t");
            const rhs = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");
            if (alias_trim.len == 0 or rhs.len == 0) continue;

            const alias_owned = try allocator.dupe(u8, alias_trim);
            const classes_owned = try allocator.dupe(u8, rhs);

            const gop = try map.getOrPut(alias_owned);
            if (gop.found_existing) {
                allocator.free(alias_owned);
                allocator.free(gop.value_ptr.*);
                gop.value_ptr.* = classes_owned;
            } else {
                gop.key_ptr.* = alias_owned;
                gop.value_ptr.* = classes_owned;
            }
        }

        return map;
    }
};

// -------------
// Unit Tests
// -------------
test "ASTNode init and deinit with attributes and children" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var root = ASTNode.init(A, .Document);
    defer root.deinit(A);

    var heading = ASTNode.init(A, .Heading);
    heading.content = "Docz Title";
    try heading.attributes.put("level", "2");
    try root.addChild(A, heading);

    try std.testing.expect(root.children.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, root.children.items[0].content, "Docz Title"));
    try std.testing.expect(root.children.items[0].attributes.contains("level"));
}

test "Css node isBlockLike and head asset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var css = ASTNode.init(A, .Css);
    defer css.deinit(A);
    try css.setContentOwned(A,
        \\.card { border: 1px solid #ccc; }
    );

    try std.testing.expect(css.isBlockLike());
    try std.testing.expect(css.isHeadAsset());
    try std.testing.expect(css.owns_content);
    try std.testing.expect(std.mem.indexOfScalar(u8, css.content, '{') != null);
}

test "StyleDef parsing: alias → classes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var def = ASTNode.init(A, .StyleDef);
    defer def.deinit(A);
    try def.setContentOwned(A,
        \\# comment
        \\heading-1: h1-xl h1-weight
        \\body-text: prose max-w-none
        \\  malformed line without colon
        \\title:   text-2xl   font-bold
    );

    var aliases = try def.parseStyleAliases(A);
    defer {
        var it = aliases.iterator();
        while (it.next()) |e| {
            A.free(e.key_ptr.*);
            A.free(e.value_ptr.*);
        }
        aliases.deinit();
    }

    try std.testing.expect(aliases.count() == 3);
    try std.testing.expect(std.mem.eql(u8, aliases.get("heading-1").?, "h1-xl h1-weight"));
    try std.testing.expect(std.mem.eql(u8, aliases.get("body-text").?, "prose max-w-none"));
    try std.testing.expect(std.mem.eql(u8, aliases.get("title").?, "text-2xl   font-bold"));
}
