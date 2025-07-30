# DEVELOPMENT.md – Engineering Guide for Docz

This document is a **technical reference for engineers contributing to Docz**.  
It focuses on the architecture, build system, debugging practices, and integration details for the **Zig-based core**, WASM runtime, and Quartz frontend.

For project planning and workflows, see:
- [ROADMAP.md](./ROADMAP.md) for strategic phases.
- [WORKFLOW.md](./WORKFLOW.md) for branching, PR, and CI/CD rules.

---

## 1. Purpose of This Document
Unlike ROADMAP or WORKFLOW, this file answers:
- **How the system is built** (architecture and components).
- **How to develop, debug, and optimize** Docz core.
- **Where to integrate** plugins, WASM modules, and UI layers.

---

## 2. High-Level Architecture

```
.dcz File
    ↓
Parser (Zig)
    ↓
AST (Intermediate Representation)
    ↓
Renderer
    ↓
Quartz UI (SvelteKit)
    ↓
Output: HTML / PDF / WASM-enhanced content
```

Key components:
- **Core Parser & CLI**: Written in Zig for deterministic builds.
- **Runtime Engine**: Executes user Zig code in a WASM sandbox.
- **UI Renderer**: Implemented in Quartz (SvelteKit + TypeScript).
- **Plugin Layer**: Extends functionality without bloating core.

---

## 3. Core Components in Detail

### 3.1 Parser
- **Goal**: Convert `.dcz` markup into an **AST**.
- Features:
    - Tokenizer for directives: `@meta`, `@heading`, `@code`, `@style`.
    - Support for **block directives** (e.g., `@code ... @end`).
- Example AST Node in Zig:
```zig
const NodeType = enum { Meta, Heading, CodeBlock, Style, Import, Math };

const ASTNode = struct {
    node_type: NodeType,
    attributes: std.StringHashMap([]const u8),
    content: []const u8,
    children: []ASTNode,
};
```

**Validation Rules**:
- Block directives must close with `@end`.
- Strict attribute validation for `@meta` and `@import`.

---

### 3.2 CLI (`qz`)
The CLI acts as the developer-facing tool:
- Commands:
    - `qz new <file>` → Create `.dcz` template.
    - `qz build <file>` → Convert `.dcz` → HTML.
    - `qz preview <file>` → Serve locally with live reload.
    - `qz install <plugin>` → Install plugins.

**CLI Skeleton in Zig**:
```zig
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    if (args.len < 2) {
        std.debug.print("Usage: qz <command>\n", .{});
        return;
    }
    // Dispatch commands...
}
```

---

### 3.3 WASM Execution Engine
- Compiles Zig code to **`wasm32-wasi`**:
```bash
zig build-lib src/runtime.zig -target wasm32-wasi --name runtime
```
- Security constraints:
    - No network or unrestricted FS access.
    - Memory limits enforced by WASM runtime.
- Future: Add **sandbox isolation layer** for plugins.

---

### 3.4 Quartz Integration (UI)
- Quartz is a **SvelteKit frontend**:
    - Renders AST → HTML dynamically.
    - Provides **hot reload** for `.dcz` files.
    - Executes WASM modules securely in-browser.
- Output format for renderer (JSON contract):
```json
{ "type": "heading", "level": 2, "content": "Introduction" }
```

---

## 4. Plugin System

- **Philosophy**: Keep core minimal; let plugins handle advanced features.
- Plugins are **Zig modules** implementing the `Plugin` struct:
```zig
const Plugin = struct {
    name: []const u8,
    register: fn () void,
};
```
- Manifest (`plugin.zon`) defines metadata and hooks.
- Key hooks: `onRegister`, `onParse`, `onRender`.

Example Plugin Manifest:
```zon
.{
    .name = "plugin-zeno",
    .version = "1.0.0",
    .hooks = .{
        "onRender" = true
    }
}
```

---

## 5. Build System & Commands

### Build Core:
```bash
zig build
```

### Run Tests:
```bash
zig build test
```

### WASM Build:
```bash
zig build-lib src/runtime.zig -target wasm32-wasi --name runtime
```

### UI (Quartz):
```bash
npm install
npm run dev
```

---

## 6. Debugging & Development Tips

### Debug Parser
```bash
zig build run -- parse examples/sample.dcz
```
Enable Zig debug logging:
```zig
std.debug.print("Token: {s}\n", .{token});
```

### Debug WASM
- Use `wasmtime` for local execution:
```bash
wasmtime runtime.wasm
```

---

## 7. Performance Guidelines
- **Goal**: Parse 10,000-line `.dcz` <100ms.
- Use **arena allocators** for AST construction.
- Avoid unnecessary copies of content strings.

---

## 8. Security Considerations
- Validate all plugin manifests before loading.
- Enforce hash verification for dependencies.
- Sandbox WASM execution fully by Phase 4.

---

## 9. Testing Standards
- Tests live **inline in Zig files**:
```zig
test "parse heading" {
    const result = try parseDocz("@heading(level=2) Title @end");
    try expectEqual(result[0].node_type, NodeType.Heading);
}
```
- 100% coverage target for parser and CLI.

Run all tests:
```bash
zig build test
```

---

## 10. Integration Points
- **Quartz UI** consumes **AST JSON** for rendering.
- **Plugins** extend via hooks.
- **CLI** orchestrates parse → render → export pipeline.

---

## 11. Related Docs
- [ROADMAP.md](./ROADMAP.md) – Strategic direction.
- [WORKFLOW.md](./WORKFLOW.md) – CI/CD & process.
- [PLUGIN_GUIDE.md](./PLUGIN_GUIDE.md) – Plugin development.
- [DEPENDENCIES.md](./DEPENDENCIES.md) – Dependency rules.
