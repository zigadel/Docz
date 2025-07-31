const std = @import("std");

// ✅ Core Parser & Renderer
pub const Tokenizer = @import("core/parser/tokenizer.zig");
pub const Parser = @import("core/parser/parser.zig");
pub const AST = @import("core/parser/ast.zig");
pub const Renderer = @import("core/renderer/html.zig");

// ✅ CLI (optional, for library-level calls)
pub const CLI = @import("core/cli/main.zig");

// ✅ Plugin System
pub const PluginManager = @import("core/plugins/manager.zig").PluginManager;
pub const Plugin = @import("core/plugins/manager.zig").Plugin;

// ✅ Aggregate all inline tests across the codebase
test {
    std.testing.refAllDecls(@This());
}
