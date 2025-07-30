# Docz Plugin Development Guide

Docz supports a **core + plugin architecture**, allowing developers to extend functionality without bloating the core. Plugins enable new directives, renderers, exporters, logic, and interactivity while maintaining security and modularity.

---

## 1. Why Plugins Matter

- **Modularity** → Keep the core lightweight.
- **Flexibility** → Add features on demand.
- **Security** → Isolate and sandbox risky operations.
- **Community Ecosystem** → Share, discover, and reuse plugins globally.

Examples of plugins:
- `plugin-zeno` → Real-time physics simulation.
- `plugin-qdraw` → Interactive diagramming.
- `plugin-python` → Execute Python code in a sandbox.
- `plugin-audio` → Execute Audio code.

---

## 2. Plugin Categories

| Category     | Purpose                                                                 |
|------------- |-------------------------------------------------------------------------|
| **Directives** | Introduce new syntax elements (e.g., `@diagram`, `@qdraw`).           |
| **Renderers**  | Define how directives render (HTML, Canvas, WebGL).                   |
| **Exporters**  | Output formats like PDF, EPUB, or Static HTML.                        |
| **Logic**      | Add interactivity or event-driven behavior.                           |
| **Themes**     | Define visual design language.                                        |

---

## 3. Plugin Anatomy

A plugin typically includes:
- **Manifest**: Metadata and directive registration.
- **Core Logic (Zig)**: Implements functionality and hooks.
- **Optional Frontend**: UI components for Quartz (SvelteKit).

### Manifest Example (`plugin.zon`)
```zon
.{
    .name = "plugin-qdraw",
    .version = "0.1.0",
    .author = "Quartz Team",
    .directives = .{
        "qdraw" = .{
            .type = "diagram",
            .description = "Draw diagrams inside Docz"
        }
    }
}
```

---

## 4. Folder Structure

```
plugin-qdraw/
├── src/
│   └── main.zig
├── plugin.zon
├── README.md
└── examples/
    └── usage.dcz
```

For JSON-based metadata (optional):
```json
{
  "name": "docz-plugin-zeno",
  "version": "1.0.0",
  "description": "Render interactive Zeno Engine scenes",
  "author": "Your Name",
  "entry": "plugin.zig",
  "hooks": {
    "register": "registerPlugin"
  }
}
```

---

## 5. Plugin Lifecycle & Hooks

Plugins integrate via **hooks**:

| Hook Name    | Purpose                                  |
|------------- |------------------------------------------|
| `onRegister` | Initialize plugin and directives.       |
| `onParse`    | Extend tokenization or AST.             |
| `onRender`   | Control rendering of custom directives. |
| `onExecute`  | Run WASM execution for code-based tasks.|
| `onTeardown` | Cleanup on shutdown.                    |

---

## 6. Writing Your First Plugin

### Step 1: Initialize
```bash
mkdir docz-plugin-hello
cd docz-plugin-hello
touch plugin.zon src/main.zig README.md
```

### Step 2: Implement Core
```zig
const std = @import("std");
pub fn registerPlugin() void {
    std.debug.print("Hello Plugin Registered!\n", .{});
}
```

---

## 7. Adding a Custom Directive

Example: `@hello(name="Docz")`

### Parsing
- Hook into `Parser` to detect `@hello(...)`.
- Inject AST node: `DirectiveNode(name="hello", params=...)`.

### Rendering
Output HTML:
```html
<p>Hello, Docz!</p>
```

---

## 8. Testing Plugins
```zig
const std = @import("std");
test "hello plugin outputs correct HTML" {
    const result = renderHello("Docz");
    try std.testing.expectEqualStrings("<p>Hello, Docz!</p>", result);
}
```
Run tests:
```bash
zig build test
```

---

## 9. Installing Plugins
Declare in `docz.zig.zon`:
```zon
.plugins = .{
    .docz-plugin-hello = .{
        .url = "https://github.com/user/docz-plugin-hello",
        .hash = "1220abc..."
    }
}
```
Install:
```bash
qz install plugin-hello
```

---

## 10. Advanced Capabilities
- **Custom Renderers**: HTML, Canvas, WebGL.
- **Secure Execution**: WASM sandboxes for untrusted code.
- **Access Document Metadata**:
```zig
pub fn onRender(meta: Meta, content: []const u8) void {
    if (meta.title) |title| {
        std.debug.print("Title: {s}\n", .{title});
    }
}
```

---

## 11. Frontend Integration
Add **Svelte components** for UI:
```
plugin-math3d/
└── ui/
    └── Math3D.svelte
```

Quartz auto-detects `ui` components via manifest.

---

## 12. Best Practices
- Use **semantic versioning**.
- Keep plugins **small and focused**.
- Validate **user input strictly**.
- Avoid heavy dependencies in core.
- Write **unit tests** for all hooks.

---

## 13. Publishing Plugins
1. Push to GitHub.
2. Tag a release.
3. Add `plugin.zon` and README.
4. Submit to **Docz Plugin Registry**.

```bash
qz publish plugin-hello
```

---

## 14. Security Guidelines
- Validate all inputs.
- Sandbox dynamic execution.
- Verify plugin hashes for integrity.

---

## 15. Example: Zeno Engine Plugin
Directive:
```
@embed(type="zeno-scene", source="scene.zson")
```
Features:
- Real-time simulation.
- WASM execution.
- WebSocket streaming.

---

## 16. Workflow Diagram
```
Plugin Source → Compile Zig → Register in manifest → Install via CLI → Use in Docz
```
