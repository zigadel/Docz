const std = @import("std");

pub const Plugin = struct {
    name: []const u8,
    onRegister: ?fn () void,
    onRender: ?fn ([]u8) []u8,
};

pub const PluginManager = struct {
    allocator: *std.mem.Allocator,
    plugins: std.ArrayList(Plugin),

    pub fn init(allocator: *std.mem.Allocator) PluginManager {
        return PluginManager{
            .allocator = allocator,
            .plugins = std.ArrayList(Plugin).init(allocator),
        };
    }

    pub fn addPlugin(self: *PluginManager, plugin: Plugin) !void {
        try self.plugins.append(plugin);
    }

    pub fn registerHooks(self: *PluginManager) void {
        for (self.plugins.items) |plugin| {
            if (plugin.onRegister) |hook| {
                hook();
            }
        }
    }

    pub fn applyRenderHooks(self: *PluginManager, html: []u8) []u8 {
        var result = html;
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
    const allocator = gpa.allocator();

    var manager = PluginManager.init(allocator);
    defer manager.plugins.deinit();

    // Reset global flags
    called_register = false;
    called_render = false;

    const plugin = Plugin{
        .name = "test-plugin",
        .onRegister = onRegisterHook,
        .onRender = onRenderHook,
    };

    try manager.addPlugin(plugin);
    manager.registerHooks();
    _ = manager.applyRenderHooks("dummy");

    try std.testing.expect(called_register);
    try std.testing.expect(called_render);
}
