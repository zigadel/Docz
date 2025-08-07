const std = @import("std");

// ─────────────────────────────────────────────
// 📦 Core Modules: Parser, Renderer, AST
// ─────────────────────────────────────────────
pub const Tokenizer = @import("src/parser/tokenizer.zig");
pub const Parser = @import("src/parser/parser.zig");
pub const AST = @import("src/parser/ast.zig");
pub const Renderer = @import("src/renderer/html.zig");

// ─────────────────────────────────────────────
// 🖥 CLI Entry Point (optional for embedding)
// ─────────────────────────────────────────────
pub const Main = @import("src/main.zig");

// ─────────────────────────────────────────────
// 🔌 Plugin System (exported types)
// ─────────────────────────────────────────────
const plugin_mod = @import("src/plugins/manager.zig");
pub const PluginManager = plugin_mod.PluginManager;
pub const Plugin = plugin_mod.Plugin;

// ─────────────────────────────────────────────
// 🧪 Aggregate all in-file (unit) tests
// ─────────────────────────────────────────────
test {
    std.testing.refAllDecls(@This());
}
