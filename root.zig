const std = @import("std");

// ✅ Core Parser & Renderer
pub const Tokenizer = @import("src/parser/tokenizer.zig");
pub const Parser = @import("src/parser/parser.zig");
pub const AST = @import("src/parser/ast.zig");
pub const Renderer = @import("src/renderer/html.zig");

// ✅ CLI (optional, for library-level calls)
pub const Main = @import("src/main.zig");

// ✅ Plugin System
pub const PluginManager = @import("src/plugins/manager.zig").PluginManager;
pub const Plugin = @import("src/plugins/manager.zig").Plugin;

// ✅ Aggregate all inline tests across the codebase
test {
    std.testing.refAllDecls(@This());
}
