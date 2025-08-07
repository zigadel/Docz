const std = @import("std");

// ─────────────────────────────────────────────
// 📦 Core Modules (Legacy Style)
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
    std.testing.refAllDecls(@This());
}
