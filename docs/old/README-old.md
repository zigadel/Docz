# Docz: The Future of Documentation

## 1. Introduction

Docz is a next-generation document format designed to replace outdated standards like Markdown, LaTeX, and Jupyter notebooks.

Modern documentation demands:

- **Human readability** (like Markdown).
- **Mathematical expressiveness** (like LaTeX).
- **Computational interactivity** (like Jupyter).

Docz combines all three in one unified, extensible syntax.

### Why Not Markdown?
- Limited expressiveness for scientific content.
- Poor AI parsing due to ambiguous syntax.
- No built-in interactivity or styling control.

### Why Not LaTeX?
- Powerful but rigid and hard to learn.
- Outdated for modern web and collaboration.

### Why Not Jupyter?
- Good for code, bad for structure.
- Fragile, bloated notebooks with hidden state issues.

**Docz bridges these gaps:**
- Human-first, AI-friendly syntax.
- Built-in support for math, media, and interactive content.
- Graph-based document model for modular composition.

---

## 2. Project Status & Vision

**Status:** Docz is in active development.

**Goal:** Replace Markdown, LaTeX, and Jupyter with a unified, future-proof format for documentation, math, and computation. 

**Ecosystem Includes:**
- **Quartz**: Modern editor for Docz.
- **VSCode Extension**: Live preview, IntelliSense, auto-formatting.
- **Zig Core**: Parser, CLI, WASM execution engine.

---

## 3. Quick Start

### Install Quartz CLI
```bash
curl -fsSL https://get.quartz.dev/install.sh | sh
```

### Create Your First Docz File
```bash
dcz new README.dcz
```

### Preview in Quartz
```bash
dcz preview README.dcz
```

---

## 4. Core Concepts

Docz is:
- **Declarative**: No hidden logic; everything is explicit.
- **Composable**: Import and reuse sections across projects.
- **Extensible**: Add new directives via plugins.

It separates:
- Structure (`@heading`, `@import`).
- Style (`@style`, `@style-def`).
- Logic (`@logic`, `@embed`).

Quartz runtime powers Docz:
- Parses `.dcz` → AST.
- Executes code in WASM sandbox.
- Renders UI in SvelteKit.

### Why Docz is Different
| Feature             | Markdown | LaTeX | Jupyter | Docz |
|---------------------|----------|-------|---------|------|
| Math Support        | Basic    | Full  | Full    | Full |
| Interactivity       | No       | No    | Yes     | Yes  |
| AI-Friendly         | No       | No    | Limited | Yes  |
| Extensible Plugins  | No       | No    | Limited | Yes  |
| WASM Execution      | No       | No    | No      | Yes  |


---

## 5. File Structure

### Minimal Example
```txt
@meta(title="Docz Example", author="Quartz Team")

@heading(level=1) Introduction
Docz is the future of documentation.

@code(language="zig", execute=true)
const x: i32 = 42;
@print(x);
@end
```

### Monograph Model
Use imports for multi-section docs:
```txt
main.dcz
chapters/
    intro.dcz
    methodology.dcz
    results.dcz
```

`main.dcz:`
```c
@import("chapters/intro.dcz")
@import("chapters/methodology.dcz")
@import("chapters/results.dcz")
```

## 6. Directives Overview

Docz introduces clear, semantic directives for every structural and interactive element (some may accept parameters).

| Directive    | Purpose                                  |
| ------------ | ---------------------------------------- |
| `@meta`      | Document metadata (title, tags, version) |
| `@heading`   | Section headings with explicit levels    |
| `@import`    | Include other `.dcz` files or styles     |
| `@style`     | Inline styling for text or blocks        |
| `@style-def` | Define global reusable styles            |
| `@code`      | Code blocks (executable for Zig)         |
| `@data`      | Embed structured data (JSON, YAML)       |
| `@math`      | Render math (LaTeX syntax)               |
| `@plot`      | Generate plots from data or functions    |
| `@graph`     | Visualize graphs or DAGs                 |
| `@image`     | Embed images                             |
| `@video`     | Embed videos                             |
| `@audio`     | Embed audio                              |
| `@embed`     | Interactive content                      |
| `@logic`     | Lightweight interactivity                |

### Math & Visualization
- `@math` → LaTeX-style equations.
- `@plot` → Data or function plots.
- `@graph` → DAG visualization.

### Media Directives
- `@media(type="image", ...)` → Generic media directive.

Shorthands:
```ts
@image(src="diagram.png")
@video(src="demo.mp4")
@audio(src="track.wav")
@pdf(src="paper.pdf")
@end
```

### Dynamic Content
- `@embed` → Interactive components (e.g., Zeno Engine scenes).
- `@logic` → Lightweight interactivity.

**Example:**
```txt
@image(src="diagram.png", onClick="play('audio1')")
@end

@logic()
function play(id) {
    document.getElementById(id).play();
}
@end
```

---

## 7. Syntax Rules

Docz syntax is explicit, minimal, and consistent.

### Inline Directives
- Single-line usage.
- No `@end` required.
- Examples: `@heading`, `@image`, `@video`, `@audio`.

```txt
@heading(level=2) Introduction
@image(src="diagram.png")
```

### Block Directives
- Multi-line content.
- Must close with @end.
- Examples: @code, @style, @style-def, @logic, @math, @plot, @graph, @embed.

```txt
@code(language="zig", execute=true)
const x: i32 = 42;
@print(x);
@end
```

### Attribute Syntax
- Use key=value format.
- Quotes optional for simple strings, required for spaces.

Example:

```txt
@style(font-size=18px, color="dark blue")
```

## Nesting Rules
- Block directives cannot be nested unless explicitly supported.
- Example of allowed future nesting: @plot inside @math.

## Imports
- @import("file.dcz") must appear at the top or inside a composition file.

## Comments
- Use // for single-line comments.

```txt
// This is a comment
```

---

## 8. Styling System

Docz separates content from presentation.

### Inline Styling

```txt
The @style(color=blue, bold) harmonic field @end emerges.
```

### Block Styling
```txt
@style(font-size=18px, font-family="Inter")
This paragraph uses custom styling.
@end
```

### Global Styles
```txt
@style-def()
heading-level-1: font-size=36px, font-weight=bold, color=#000
body-text: font-family="Inter", line-height=1.6
@end
```

### External Styles
```ts
@import("styles/academic.dczstyle")
```

**Override Priority:** Inline > Local @style-def > Imported theme.

## 9. Execution Model

- Language: Zig first.
- Run Mode: Secure WASM sandbox.

Example:
```
@code(language="zig", execute=true)
const nums = [_]i32{1,2,3,4,5};
const sum = @reduce(.Add, nums);
@print(sum);
@end
```

Why Zig?
- WASM-native, deterministic, safe.
- Aligns with Quartz + Zeno ecosystem.

**Future:** Plugin-based multi-language execution.

---

## 10. Media & Interactivity

Bring documents to life with images, video, audio, PDFs, and interactive embeds.

### Static Media

```txt
@image(src="figures/diagram.png", width="600px", caption="System Architecture")
@end

@video(src="clips/demo.mp4", width="800px", controls=true)
@end
```

### Dynamic Content
```
@embed(type="zeno-scene", source="scenes/fluid.zscene", width="800px", interactive=true)
@end
```

### Advanced Options
- `width`, `height`, `align`, `responsive=true`.

Example:
```ts
@image(src="diagram.png", width="600px", align="center", responsive=true)
@end
```

### Lightweight Logic

```txt
@image(src="diagram.png", onClick="play('narration')")
@end

@audio(id="narration", src="audio/explanation.wav", controls=false)
@end

@logic()
function play(id) {
    const audio = document.getElementById(id);
    audio.play();
}
@end
```

### Advanced Media Options
All media directives support:
- `width`, `height` → Size control.
- `align` → `left`, `center`, `right`.
- `responsive=true` → Auto-resize.

#### Example:
```txt
@image(src="diagram.png", width="600px", align="center", responsive=true)
@end
```

#### Zeno Engine Integration
```txt
@embed(type="zeno-scene", source="scenes/fluid.zscene", width="900px", height="600px", interactive=true)
@end
```

---

## 11. Composition & Imports
Organize docs like modular code.

Example:
```
@import("chapters/intro.dcz")
@import("chapters/methodology.dcz")
```

Quartz automatically builds an **import** DAG:

```txt
main.dcz -> intro.dcz -> methodology.dcz
```

---

## 12. Graph & ZUQL Integration

Docz is graph-native:

- Every @import, tag, and link builds a semantic Directed Acyclic Graph (DAG).
- Visualize your document structure or query it with ZUQL.

### Example: Visualize Imports (multiple formats accepted)

Variant 1:
```txt
@graph(type="imports")
nodes:
    - main.dcz
    - chapters/intro.dcz
    - chapters/methodology.dcz
edges:
    - main.dcz -> chapters/intro.dcz
    - main.dcz -> chapters/methodology.dcz
@end
```

Variant 2:
```txt
@graph(type="imports")
nodes: [main.dcz, intro.dcz]
edges: [main.dcz -> intro.dcz]
@end
```
### Example: ZUQL Queries

```sql
SHOW DAG FOR main.dcz;
SELECT docs WHERE tag="math" AND status="draft";
```

---

## 13. Plugin System

### Why Plugins?

- Keep Docz core lean and dependency-free.
- Enable heavy features only when needed (e.g., 3D rendering, Zeno Engine).

### Install Plugins

```bash
dcz install plugin-zeno
dcz install plugin-3d-model
dcz install plugin-vulkan
dcz install plugin-webgpu
dcz install plugin-python
```

### Add Custom Directives

```text
@register-directive(name="qdraw", type="diagram")
@end
```

#### Plugin Types:

- Renderers: Zeno Engine, diagrams, 3D models.
- Exporters: PDF, ePub, HTML.
- Interactivity: Real-time collaboration.

---

## 14. Architecture Overview

Docz runtime architecture:

```
.dcz → Quartz Parser → WASM Core → SvelteKit UI
```

### Components

- Docz Parser: Tokenizes and builds AST.
- WASM Core: Executes Zig securely.
- Quartz UI: Renders layout, interactivity, and media.

`@diagram`:

```txt
+----------------+
| .dcz Document  |
+--------+-------+
         |
         v
+--------+-------+
| Quartz Parser  |
+--------+-------+
         |
         v
+--------+-------+
|  WASM Core     |
+--------+-------+
         |
         v
+--------+-------+
| SvelteKit UI   |
+----------------+
```

---

## 15. CLI Reference

Quartz CLI: `dcz`

| Command      | Description               |
| ------------ | ------------------------- |
| `dcz new`     | Create a new Docz file    |
| `dcz preview` | Live preview in Quartz UI |
| `dcz build`   | Compile to HTML/PDF       |
| `dcz install` | Install plugins           |

### Examples

```bash
dcz new README.dcz
dcz preview README.dcz
dcz build main.dcz --output docs/
```

---

## 16. Advanced Examples

### Monograph

```c
@import("chapters/intro.dcz")
@import("chapters/methodology.dcz")
@import("chapters/results.dcz")
```

### Math + Plot

```txt
@math()
E = mc^2
@end

@plot(type="line")
x: [1,2,3,4,5]
y: [1,4,9,16,25]
@end
```

### Media + Interactivity

```txt
@image(src="diagram.png", onClick="play('narration')")
@end

@audio(id="narration", src="audio/explanation.wav", controls=false)
@end

@logic()
function play(id) {
    const audio = document.getElementById(id);
    audio.play();
}
@end
```

---

## 17. Roadmap

- Collaboration: Real-time multi-user editing.
- AI Integration: Semantic suggestions, auto-formatting.
- Plugin Marketplace: Discover and share extensions.
- Native Quartz: Zig + WebGPU backend for high-performance rendering.

---

## 18. Tooling & Extensions
- **VSCode Extension**: Live preview like Markdown, IntelliSense for Docz directives, auto-formatting & linting powered by the Zig parser (via WASM).
- **Quartz Integration**: Full interactive editor built on SvelteKit.

---

## 19. Contributing

- Code: Written in Zig with strict test coverage.
- Style: Follow zero-dependency philosophy for Docz core.
- Testing: Use Zig’s built-in test blocks for every parser function.
- PRs welcome for:
    - Plugins.
    - Theme packs.
    - Rendering optimizations.

### Development Workflow
- Parser & CLI written in Zig.
- 100% test coverage on AST parser.
- `.github/` folder includes:
    - Issue & PR templates.
    - CI workflows (build, test, release).
- Run tests: `zig build test` (for unit tests), `test-integration`, `test-e2e`, or `test-all`