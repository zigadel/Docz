// "public API surface" (internal stuff is instead hooked up via `build.zig`)
const std = @import("std");

// ── Public modules
pub const Tokenizer = @import("src/parser/tokenizer.zig");
pub const Parser = @import("src/parser/parser.zig");
pub const AST = @import("src/parser/ast.zig");
pub const Renderer = @import("src/renderer/html.zig");

// NOTE: DO NOT import src/main.zig here (avoids module ownership conflict)

// ── Plugin system
const plugin_mod = @import("src/plugins/manager.zig");
pub const PluginManager = plugin_mod.PluginManager;
pub const Plugin = plugin_mod.Plugin;

// ── Web preview
const web_preview_server = @import("web-preview/server.zig");
const web_preview_hot_reload = @import("web-preview/hot_reload.zig");
pub const web_preview = struct {
    pub const server = web_preview_server;
    pub const hot = web_preview_hot_reload;
};

// ── Namespaces for clarity
pub const parser = struct {
    pub const tokenizer = Tokenizer;
    pub const parser = Parser;
    pub const ast = AST;
};
pub const renderer = struct {
    pub const html = Renderer;
};

// ── Minimal shim for tests that read docz.main.USAGE_TEXT
pub const main = struct {
    pub const USAGE_TEXT =
        \\Docz CLI Usage:
        \\  docz build <file.dcz>       Build .dcz file to HTML
        \\  docz preview                Start local preview server
        \\  docz enable wasm            Enable WASM execution support
        \\
    ;
};

test {
    std.testing.refAllDecls(@This());
    comptime {
        _ = web_preview.server.PreviewServer;
        _ = web_preview.hot.Broadcaster;
        _ = web_preview.hot.Sink;
    }
}
