const std = @import("std");

// ─────────────────────────────────────────────
// 📦 Core Modules
// ─────────────────────────────────────────────
pub const Tokenizer = @import("src/parser/tokenizer.zig");
pub const Parser = @import("src/parser/parser.zig");
pub const AST = @import("src/parser/ast.zig");
pub const Renderer = @import("src/renderer/html.zig");
pub const Main = @import("src/main.zig");

// ─────────────────────────────────────────────
// 🔌 Plugin System (exported types)
// ─────────────────────────────────────────────
const plugin_mod = @import("src/plugins/manager.zig");
pub const PluginManager = plugin_mod.PluginManager;
pub const Plugin = plugin_mod.Plugin;

// ─────────────────────────────────────────────
// 🌐 Web Preview (server + hot-reload)
// ─────────────────────────────────────────────
const web_preview_server = @import("web-preview/server.zig");
const web_preview_hot = @import("web-preview/hot_reload.zig");

/// Public namespace for web-preview utilities
pub const web_preview = struct {
    /// HTTP preview server (SSE endpoint + static files)
    pub const server = web_preview_server;

    /// Hot reload broadcaster/SSE sink interface
    pub const hot = web_preview_hot;
};

// ─────────────────────────────────────────────
// 📦 Structured Namespaces (for tests / clarity)
// ─────────────────────────────────────────────
pub const parser = struct {
    pub const tokenizer = Tokenizer;
    pub const parser = Parser;
    pub const ast = AST;
};

pub const renderer = struct {
    pub const html = Renderer;
};

pub const main = Main;

// ─────────────────────────────────────────────
// 🧪 Aggregate all in-file (unit) tests
// ─────────────────────────────────────────────
test {
    // Ensure all public decls get type-checked
    std.testing.refAllDecls(@This());

    // Light compile-time checks that the web-preview types are present
    comptime {
        _ = web_preview.server.PreviewServer;
        _ = web_preview.hot.Broadcaster;
        _ = web_preview.hot.Sink;
    }
}
