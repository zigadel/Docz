
const std = @import("std");

/// Represents the canonical spelling of a directive, with aliases and metadata.
pub const DirectiveSpec = struct {
    name: []const u8,                 // canonical name, e.g. "heading"
    aliases: []const []const u8,      // e.g. ["h", "hdr"]
    requires_end: bool,               // does it require @end?
    description: []const u8,          // short summary

    pub fn matches(self: DirectiveSpec, ident: []const u8) bool {
        if (std.ascii.eqlIgnoreCase(ident, self.name)) return true;
        for (self.aliases) |a| {
            if (std.ascii.eqlIgnoreCase(ident, a)) return true;
        }
        return false;
    }
};

/// Registry: holds core directives + plugin registrations
pub const Registry = struct {
    arena: std.heap.ArenaAllocator,
    table: std.StringHashMap(*const DirectiveSpec),

    pub fn init(allocator: std.mem.Allocator) Registry {
        var arena = std.heap.ArenaAllocator.init(allocator);
        return Registry{
            .arena = arena,
            .table = std.StringHashMap(*const DirectiveSpec).init(arena.allocator()),
        };
    }

    pub fn deinit(self: *Registry) void {
        self.table.deinit();
        self.arena.deinit();
    }

    /// Register a directive spec (canonical + aliases).
    pub fn register(self: *Registry, spec: DirectiveSpec) !void {
        const alloc = self.arena.allocator();
        const spec_ptr = try alloc.create(DirectiveSpec);
        spec_ptr.* = spec;
        try self.table.put(spec.name, spec_ptr);
        for (spec.aliases) |a| {
            try self.table.put(a, spec_ptr);
        }
    }

    /// Look up by name or alias; returns canonical spec or null if unknown.
    pub fn lookup(self: *Registry, ident: []const u8) ?*const DirectiveSpec {
        return self.table.get(ident);
    }

    /// Normalize an identifier to canonical name (if known), else return original.
    pub fn normalize(self: *Registry, ident: []const u8) []const u8 {
        if (self.lookup(ident)) |spec| return spec.name;
        return ident;
    }
};

/// Initialize a registry with all core directives and their common shorthands.
pub fn initCoreRegistry(allocator: std.mem.Allocator) !Registry {
    var r = Registry.init(allocator);

    try r.register(.{
        .name = "meta",
        .aliases = &.{ "m" },
        .requires_end = true,
        .description = "Document metadata (title, author, etc.)",
    });

    try r.register(.{
        .name = "heading",
        .aliases = &.{ "h", "hdr" },
        .requires_end = true,
        .description = "Section heading (level=1..6)",
    });

    try r.register(.{
        .name = "paragraph",
        .aliases = &.{ "p" },
        .requires_end = true,
        .description = "Paragraph block (usually implicit)",
    });

    try r.register(.{
        .name = "code",
        .aliases = &.{ "c" },
        .requires_end = true,
        .description = "Code block",
    });

    try r.register(.{
        .name = "math",
        .aliases = &.{ "equation" },
        .requires_end = true,
        .description = "Math block",
    });

    try r.register(.{
        .name = "image",
        .aliases = &.{ "img" },
        .requires_end = false,
        .description = "Image/media embed",
    });

    try r.register(.{
        .name = "import",
        .aliases = &.{ "include" },
        .requires_end = false,
        .description = "Import external resource (css/js)",
    });

    try r.register(.{
        .name = "style",
        .aliases = &.{ "css" },
        .requires_end = true,
        .description = "Inline stylesheet block",
    });

    return r;
}

test "registry basic normalize and lookup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var r = try initCoreRegistry(alloc);
    defer r.deinit();

    const n1 = r.normalize("H"); // alias
    try std.testing.expect(std.mem.eql(u8, n1, "heading"));

    const n2 = r.normalize("code");
    try std.testing.expect(std.mem.eql(u8, n2, "code"));

    const n3 = r.normalize("unknown");
    try std.testing.expect(std.mem.eql(u8, n3, "unknown"));

    const spec = r.lookup("hdr").?;
    try std.testing.expect(std.mem.eql(u8, spec.name, "heading"));
}
