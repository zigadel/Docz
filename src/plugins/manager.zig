const std = @import("std");

pub const Plugin = struct {
    name: []const u8,
    // Use function pointers so the struct is a runtime type (not comptime-only).
    onRegister: ?*const fn () void = null,
    onRender: ?*const fn ([]u8) []u8 = null,
};

pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(Plugin),

    /// Initialize the PluginManager with a given allocator
    pub fn init(allocator: std.mem.Allocator) PluginManager {
        return .{
            .allocator = allocator,
            .plugins = std.ArrayList(Plugin){}, // no .init() on this Zig build
        };
    }

    /// Properly free all allocated resources
    pub fn deinit(self: *PluginManager) void {
        self.plugins.deinit(self.allocator);
    }

    /// Add a new plugin to the manager
    pub fn addPlugin(self: *PluginManager, plugin: Plugin) !void {
        try self.plugins.append(self.allocator, plugin);
    }

    /// Execute all registered onRegister hooks
    pub fn registerHooks(self: *PluginManager) void {
        for (self.plugins.items) |plugin| {
            if (plugin.onRegister) |hook| {
                hook();
            }
        }
    }

    /// Apply all onRender hooks to the given HTML input
    /// Returns a duplicated mutable buffer; caller must free.
    pub fn applyRenderHooks(self: *PluginManager, html: []const u8) ![]u8 {
        var result = try self.allocator.dupe(u8, html); // Create mutable copy
        // IMPORTANT: We return this buffer to caller; caller must free it.
        for (self.plugins.items) |plugin| {
            if (plugin.onRender) |hook| {
                result = hook(result);
            }
        }
        return result;
    }
};

// ----------------------
// Tests
// ----------------------
var called_register: bool = false;
var called_render: bool = false;

fn onRegisterHook() void {
    called_register = true;
}

fn onRenderHook(html: []u8) []u8 {
    called_render = true;
    return html;
}

test "PluginManager adds and applies hooks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const A = gpa.allocator();

    var manager = PluginManager.init(A);
    defer manager.deinit();

    // Reset global flags
    called_register = false;
    called_render = false;

    const plugin = Plugin{
        .name = "test-plugin",
        .onRegister = &onRegisterHook,
        .onRender = &onRenderHook,
    };

    try manager.addPlugin(plugin);
    manager.registerHooks();

    const output = try manager.applyRenderHooks("dummy");
    defer A.free(output);

    try std.testing.expect(called_register);
    try std.testing.expect(called_render);
}
