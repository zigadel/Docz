// "public API surface" (internal stuff is instead hooked up via `build.zig`)
const std = @import("std");

// ── Parsers / AST -----------------------------------------------------------
pub const Tokenizer = @import("src/parser/tokenizer.zig");
pub const Parser = @import("src/parser/parser.zig");
pub const AST = @import("src/parser/ast.zig");

// Import the dedicated HTML exporter module (wired up in build.zig).
// NOTE: build.zig must have: docz_module.addImport("html_export", html_export_mod);
const html_export = @import("html_export");

// ── Renderer facade (what tests/CLI import) ---------------------------------
// - renderer.inline.renderInline(...)   → inline transformer for paragraph text
// - renderer.html.exportHtml(...)       → full document HTML exporter
//   (aliases: renderer.html.renderHTML / renderer.html.render)
pub const renderer = struct {
    pub const inline_ = struct {
        pub const renderInline =
            @import("src/renderer/inline.zig").renderInline;
    };

    pub const html = struct {
        pub const exportHtml = html_export.exportHtml;

        // Convenience aliases expected by some callers/tests
        pub const render = exportHtml;
        pub const renderHTML = exportHtml;
    };
};

// ── Canonical top-level symbols (back-compat) --------------------------------
// Some older call sites use these names directly.
pub const Renderer = @import("src/renderer/html.zig");
pub const InlineRenderer = @import("src/renderer/inline.zig");

// ── Embedded assets (paths are relative to repo root) -----------------------
pub const assets = struct {
    /// Baseline stylesheet for out-of-the-box, clean defaults.
    pub const core_css: []const u8 = @embedFile("assets/css/docz.core.css");
};

// ── Plugin system ------------------------------------------------------------
const plugin_mod = @import("src/plugins/manager.zig");
pub const PluginManager = plugin_mod.PluginManager;
pub const Plugin = plugin_mod.Plugin;

// ── Namespaces for clarity (ergonomic re-exports) ---------------------------
pub const parser = struct {
    pub const tokenizer = Tokenizer;
    pub const parser = Parser;
    pub const ast = AST;
};

// ── Minimal shim for tests that read docz.main.USAGE_TEXT -------------------
pub const main = struct {
    pub const USAGE_TEXT =
        \\Docz CLI Usage:
        \\  docz build <file.dcz>       Build .dcz file to HTML
        \\  docz preview                Start local preview server
        \\  docz enable wasm            Enable WASM execution support
        \\
    ;
};

// Keep tests tiny; no cross-module imports from here to avoid cycles.
test {
    std.testing.refAllDecls(@This());
}
