# STYLE_GUIDE.md – The Unified Design Language for Docz

Docz is more than a documentation engine—it is **the future of structured knowledge**.  
This style guide defines the **rules, rationale, and principles** that keep our ecosystem consistent, secure, and timeless.

It applies to:
- **Docz Markup Language** (`.dcz` files)
- **Core & Plugin Development in Zig**
- **Project Structure & Testing**
- **Security and Performance Practices**

---

## 1. Purpose of This Guide

Consistency is not cosmetic—it is **architectural integrity**.  
Docz aims to become the **universal standard for declarative documentation**, and that requires:
- **Predictability:** Anyone can read and reason about a `.dcz` file or Zig module without surprises.
- **Extensibility:** Rules that allow evolution without chaos.
- **Security by Design:** Avoiding ambiguity that leads to vulnerabilities.

This guide is the **social contract for style**, ensuring **clarity, composability, and trust** in every line of code and every directive.

---

## 2. Design Principles

Before rules, understand **why they exist**:
- **Explicitness over Implicitness:** Hidden conventions create bugs and security holes.
- **Flatness over Nesting:** Complexity increases attack surface and cognitive load.
- **Semantic Rigor:** Every directive and function should express its intent clearly.
- **Separation of Concerns:** Content, presentation, and logic are distinct layers.
- **Security First:** Every design decision considers attack vectors and sandbox compliance.

---

## 3. Docz Markup Style (`.dcz`)

### 3.1 Core Rules and Their Rationale
✅ **Explicit directives only** (`@heading`, `@meta`) → Prevent ambiguity from Markdown-like syntax.  
✅ **Minimal nesting** → Keeps parsing predictable and secure.  
✅ **Parameter-driven config** → Avoid inline hacks that break determinism.  
✅ **Always close blocks** → Ambiguous termination invites parser errors and injection risk.

---

### 3.2 Document Structure
- **Metadata first**: Establish identity and context upfront.
```dcz
@meta(title="Docz Example", author="Quartz Team", version="1.0")
```

- **Imports before content**: Declarative ordering avoids hidden dependencies.
```dcz
@import("styles/academic.dczstyle")
```

- **Explicit block closure**:
```dcz
@heading(level=2) Quick Start
@end
```

---

### 3.3 Directive Syntax Rules
- **Start with `@`** → Makes parsing deterministic.
- **Parameters use `key=value` pairs**.
- **Quote strings with spaces** → No ambiguity in parsing.
- **Examples:**
```dcz
@code(language="zig", execute=true)
const x = 42;
@end
```

**Why?** → Prevents silent failures and enforces structural clarity.

---

### 3.4 Naming Conventions
- **Files:** `kebab-case` → `getting-started.dcz`.
- **Directives:** lowercase → `@heading`, not `@Heading`.
- **Why?** → Lowercase directives reduce lexical complexity for parser.

---

### 3.5 Indentation & Formatting
- **Directives unindented**, nested content indented by 4 spaces.
- **Why?** → Consistent visual hierarchy for readability and parsing predictability.

---

### 3.6 Comments
```dcz
#: This is a comment
```
**Why?** → Uses a unique marker to avoid conflict with directive syntax.

---

### 3.7 Linting Rules
- All block directives must end with `@end`.
- Validate asset paths.
- Disallow unused styles.
**Why?** → Enforces hygiene and prevents runtime failures.

---

## 4. Zig Code Style for Core & Plugins

### 4.1 Naming
- **Types & Structs:** `CamelCase` → `ASTNode`.
- **Functions:** `camelCase` → `parseDoczFile`.
- **Constants:** `UPPER_CASE` → `MAX_BUFFER`.
- **Variables:** `snake_case` → `node_list`.
**Why?** → Each style signals intent (type vs function vs constant).

---

### 4.2 Error Handling
- Use Zig idioms:
```zig
const file = try std.fs.cwd().openFile("docz.dcz", .{});
```
- **No `catch unreachable`** outside tests.
**Why?** → Failure paths must be explicit to maintain determinism.

---

### 4.3 Layout & Formatting
- **Max line length:** 100 chars.
- **Group imports at top:**
```zig
const std = @import("std");
const parser = @import("parser.zig");
```

---

### 4.4 Documentation
- Use `///` for public APIs:
```zig
/// Parses a Docz file and returns AST.
pub fn parseDoczFile(path: []const u8) !ASTNode { ... }
```

---

## 5. Plugin Development Standards

### 5.1 Manifest Format
Plugins declare metadata in `.zon`:
```zon
.{
    .name = "plugin-zeno",
    .version = "1.0.0",
    .hooks = .{ "onRegister" = true }
}
```

### 5.2 Hook Names
- Reserved:
    - `onRegister` → Plugin bootstrap.
    - `onParse` → Modify AST.
    - `onRender` → Affect output.

### 5.3 Directory Layout
```
plugin-name/
├── plugin.zon
└── src/main.zig
```

---

## 6. Project Structure Rules
```
docz/
    core/           # Parser, CLI, runtime
    plugins/        # Official plugins
    examples/       # Sample .dcz files
    docs/           # Internal documentation
```

---

## 7. Testing Standards
- Tests live inline in `.zig` files:
```zig
test "parse heading" {
    const result = try parseDocz("@heading(level=2) Title @end");
    try expectEqual(result[0].node_type, NodeType.Heading);
}
```
- Descriptive test names.
- **No separate `tests/` folder** → Tests travel with code for cohesion.

---

## 8. Security & Performance Principles

### Security:
- **Hash-verify all plugins**.
- **Sandbox WASM execution**.
- **Fail closed, not open** → Default to safety.

### Performance:
- **Zero-copy parsing** where possible.
- **Arena allocators** over global state.
- **Rationale:** These rules preserve speed and determinism without compromising safety.

---

## 9. Related Docs
- [CONTRIBUTING.md](../.github/CONTRIBUTING.md)
- [ROADMAP.md](./ROADMAP.md)
- [WORKFLOW.md](./WORKFLOW.md)
- [PLUGIN_GUIDE.md](./PLUGIN_GUIDE.md)

---

**Last Updated:** {Insert Date}
