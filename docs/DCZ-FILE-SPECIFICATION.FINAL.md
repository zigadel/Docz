# DCZ File Specification — Reconciled GOLD (Markdown)

**Source of truth:** `DCZ-FILE-SPECIFICATION.revised(1).dcz` (size: 53444 bytes).  
**Generated:** 2025-09-02T12:46:34.945877Z

This Markdown mirrors the current canonical `.dcz` specification exactly in the appendix below,
so you can paste this file into other threads or repos and retain the exact examples and directives.
When in doubt, the fenced `.dcz` appendix is authoritative.

---

## Appendix A — Canonical `.dcz` specification (verbatim)

```dcz
@meta(title="Docz – DCZ File Specification (Draft)", author="Docz Authors", version="0.1.0")
@end

@meta(title="Docz Specification — Section 1: Introduction", author="Docz Authors", section="1")
```

# 1. Introduction

Docz is a **document language and toolchain** designed to make technical writing — from STEM notes and research papers to specs, guides, and documentation — **as clear, fast, and programmable as possible**.

It combines the familiarity of Markdown with the precision of LaTeX and the interactivity of modern notebooks, while avoiding their limitations. Docz compiles to **portable HTML + CSS (+ optional WASM)** and stays readable to both **humans** and **AI**.

## 1.1 What Docz Gives You

- **Markdown-like brevity** for everyday writing (headings, lists, links).
- **First-class math, code blocks, and styling** through declarative `@directives`.
- **Deterministic compilation** to clean HTML that is portable, themeable, and easy to style.
- **Optional power-ups:** Tailwind themes, KaTeX math, syntax highlighting, and live preview.
- **A single, uniform model:** shorthand when you want speed, explicit directives when you need precision.

## 1.2 Why Docz Exists

Existing tools fall short:

- **Markdown** is convenient, but underspecified and inconsistent across flavors.
- **LaTeX** is precise, but verbose, brittle, and slow to iterate on.
- **Jupyter-style notebooks** are interactive, but tied to a runtime and awkward to version.
- **Web Development** (**HTML** + **CSS** + **JS/TS** + **WASM**) is all-powerful but not beginner-friendly

Docz unifies the strengths of all four: **simplicity, clarity, interactivity, portability** — with a grammar that’s explicit enough for machines and ergonomic enough for humans.

## 1.3 Core Philosophy

- **Clarity first.** Documents should be easy to read and parse (for humans and AI).
- **Explicit, Intuitive, and Ergonomic.** Everything has a canonical explicit form; shorthand is optional.
- **Programmable by design.** Text, math, code, and interactive views compose cleanly.
- **No hidden global state.** What you write is what gets rendered.
- **Future‑proof output.** Docz targets stable web primitives (HTML/CSS/WASM).

Docz lets you stay **minimal when you want brevity** — and **explicit when you need control**.

## 1.4 Programmability via WASM

Docz is not only about text and formatting — it is also a **programmable document format**. Through **WebAssembly (WASM)**, `.dcz` files can embed live, sandboxed code that executes at render time.

- **Zig‑first.** Docz is written in Zig, and Zig compiles to WASM seamlessly. Zig is the first‑class supported language for inline execution.
- **Language‑agnostic by design.** Any language that targets WASM (Rust, C, Go, AssemblyScript, etc.) can run inside Docz.
- **Deterministic + portable.** The result is a single HTML document with optional WASM modules — easy to version, host, and share.
- **Security‑aware.** Execution is sandboxed; actions are explicit. (Docz favors opt‑in features over magic defaults.)

With WASM enabled, Docz becomes a superset of Markdown/LaTeX and a portable alternative to traditional notebooks: **text, math, code, and interactive views in one coherent format**.

# Quick Glimpse

Docz feels like Markdown when you want speed, and like a tiny, programmable document language when you need precision.

## 1. Begin by defining Metadata of the `.dcz` file

There are two acceptable syntaxes for this.

### a. Metadata-as-parameters of `@meta`

```
@meta(title="Mathematics — Ring-Theory x Geometry", author="Smarty Pants")
```

### b. Metadata-as-body of `@meta`

```
@meta
title="Mathematics — Ring-Theory x Geometry", 
author="Smarty Pants",
prerequisite_knowledge=["prelude", "vol5", "vol7", "vol9.ch1", "vol9.ch2"],
relevant_fields_of_study=["analytic_geometry", "number_theory", "ring theory"]
relevant_people=["Carl Gauss", "Isaac Newton", "Lagrange",  "Cauchy", "Emmy Noether"]
@end
```

### c. Hybrid metadata-as-parameters & body

```
@meta(title="Mathematics — Ring-Theory x Geometry", author="Smarty Pants")
prerequisite_knowledge=["prelude", "vol5", "vol7", "vol9.ch1", "vol9.ch2"],
relevant_fields_of_study=["analytic_geometry", "number_theory", "ring theory"]
relevant_people=["Carl Gauss", "Isaac Newton", "Lagrange",  "Cauchy", "Emmy Noether"]
@end
```

## 2. Definine Section Headers

### a. Explicit Syntaxes

#### (i)

```
@heading(level=1)Welcome to Wrestlemania.com!@end

@heading(level=2)Ticket Prices@end

@heading(level=2)Tour Locations@end
```

#### (ii)

```
@heading(level=1){Welcome to Wrestlemania.com!}

@heading(level=2){Ticket Prices}

@heading(level=2){Tour Locations}
```

### b. `.md`-inspired shorthand syntax

```
# Welcome to Wrestlemania.com!

## Ticket Prices

## Tour Locations
```

### c. Raw `HTML` in `.dcz` 

```
<h1>Welcome to Wrestlemania.com</h1>
<h2>Ticket Prices</h2>
<h2>Tour Locations</h2>
```

---

### Unaccounted text is placed in `<section>`

---

### Paragraph (shorthand).

#### Docz-explicit syntax

```sh
@p(class="text-green-500")
Some random text.
@end
```

#### Raw HTML is understood in `.dcz` files

```html
<p></p>
```

### Metadata

```sh
@meta(title="Docz Spec — Section 3: Directives Overview", author="Docz Authors")
```


---


### Example: Einstein’s insight

### Example: Einstein’s insight

```dcz
@math
E = mc^2
@end

@style(class="note")
This equation shows how mass and energy are interchangeable.
@end

- Write equations inline: $F = ma$
- Link like Markdown: [Zig](https://ziglang.org)
- Style inline with a one-liner: @(class="highlight"){important}
- Or the block form when you need multiple lines:
@style(class="callout")
Multiple lines of emphasized prose.
Still readable. Still minimal.
@end
```

## Code feels natural
```dcz
@code(lang="zig")
const std = @import("std");
pub fn main() void {
    std.debug.print("Hello from Zig!\n", .{});
}
@end
```

---

# 3. Directives Overview

Directives are Docz’s core building blocks. A directive is an explicit block with a name, optional attributes, and content:

```text
@name(attr="value", attr2="value2")
  content…
@end
```

Directives are **unambiguous** for parsers and **ergonomic** for humans. Most everyday constructs also have a **shorthand** form that compiles to the same output.

## 3.1 Shorthand vs Explicit

Shorthand is fast to write; explicit form is canonical and guaranteed to be unambiguous. Both are equivalent.

@style(class="example-grid")
@code(lang="dcz")
# Shorthand
# Title (h1)
## Section (h2)

# Explicit
@heading(level=1) Title @end
@heading(level=2) Section @end
@end
@end

Paragraphs:
@style(class="example-grid")
@code(lang="dcz")
# Shorthand
This is a paragraph.

# Explicit
@p
This is a paragraph.
@end
@end
@end

## 3.2 Inline vs Block

**Inline directives** live inside a paragraph; **block directives** span multiple lines.

Inline styling (two ways — explicit and shorthand):

@style(class="example-grid")
@code(lang="dcz")
# Explicit inline style
The force is @style(class="highlight") mass @end important.

# Shorthand inline style
The force is @(class="highlight"){mass} important.
@end
@end

Block examples:

@style(class="example-grid")
@code(lang="dcz")
@math
E = mc^2
@end

@code(lang="bash")
zig build run -- run ./examples/hello.dcz
@end
@end
@end

## 3.3 Equivalence & Parsing Guarantees

- Shorthand is **syntactic sugar** for directives.
- Every shorthand form has a stable explicit counterpart.
- Parsers and tools can always normalize with `docz convert --explicit`.

## 3.4 Raw HTML Escape Hatch

Use raw HTML for special elements (`<details>`, `<canvas>`, custom widgets). Prefer Docz directives when possible.

```dcz
<p class="note">Raw HTML block — use sparingly.</p>
```

## 3.5 Attribute Rules

- Attributes use `key="value"` (double quotes required).
- Booleans are strings: `enabled="true"` / `enabled="false"`.
- Multiple classes go in one string: `class="prose text-sm italic"`.
- Prefer `class="..."` for utilities/themes; use `style="..."` for ad-hoc CSS.

Inline style examples:

@style(class="example-grid")
@code(lang="dcz")
# Utility-first
@style(class="text-blue-600 font-semibold") Link @end

# Ad-hoc CSS
@style(style="color:#0a0; text-decoration:underline") Green @end
@end
@end

## 3.6 Nesting (Inline + Block)

Directives compose. Keep nesting shallow for readability.

@style(class="example-grid")
@code(lang="dcz")
@style(class="callout")
  @heading(level=3) Note @end
  You can emphasize @(class="underline"){key} terms even inside rich blocks.
@end
@end
@end

---

**Next:** Section 4 covers the standard block directives in detail (headings, paragraphs, math, code, and style).

---

# 4. Block Directives

## 4.1 Headings

Shorthand:

```dcz
# Level 1 Heading
## Level 2 Heading
### Level 3 Heading
#### Level 4 Heading
##### Level 5 Heading
###### Level 6 Heading
```

Explicit:

```dcz
@heading(level=1) Level 1 Heading @end
@heading(level=2) Level 2 Heading @end
@heading(level=3) Level 3 Heading @end
@heading(level=4) Level 4 Heading @end
@heading(level=5) Level 5 Heading @end
@heading(level=6) Level 6 Heading @end
```

> Use shorthand while drafting; `docz convert --explicit` for canonical storage.

## 4.2 Paragraphs

Paragraphs are inferred from text separated by a blank line.

```dcz
This is a paragraph.
It continues on the next line.

This is a new paragraph.
```

## 4.3 Code Blocks

Explicit only (no Markdown backticks). Specify `lang` for tooling/themes.

```dcz
@code(lang="zig")
const std = @import("std");
pub fn main() void {
    std.debug.print("Hello, world!\n", .{});
}
@end
```

## 4.4 Math Blocks

Rendered with KaTeX (when assets are available). Content is LaTeX math.

```dcz
@math
E = mc^2
@end
```

- Inline math: `$ ... $`.  
- Display math: `@math ... @end`.

## 4.5 Style Blocks

Wrap content and apply CSS classes or inline styles.

Class-based:

```dcz
@style(class="prose lg:prose-xl text-slate-800")
This paragraph is rendered with larger, readable typography.
@end
```

Inline CSS:

```dcz
@style(style="background:#111; color:#eee; padding:12px; border-radius:8px")
Dark panel with inline CSS.
@end
```

> Prefer `class="..."` for utilities or named classes; `style="..."` for one-offs.

## 4.6 Global Styles: Aliases and Raw CSS

Aliases (last write wins):

```dcz
@style(mode="global")
heading-hero: text-4xl font-extrabold tracking-tight
body-copy: prose prose-slate max-w-none
callout: ring-1 ring-amber-300 bg-amber-50 rounded-md p-3
@end
```

Using aliases:

```dcz
@style(name="heading-hero")
Block Aliases Make Styling Readable
@end

@style(name="callout")
This block uses the `callout` alias defined above.
@end
```

Raw CSS:

```dcz
@css
.badge { display:inline-block; padding:.15rem .5rem; border-radius:.375rem; background:#eef; color:#225; }
.k { color:#0a7; text-decoration:underline dotted; }
@end
```

## 4.7 Media (Images)

```dcz
@media(src="./img/diagram.png" alt="Architecture Diagram" title="System Overview")
@end
```

> For video/audio, prefer raw HTML tags until dedicated directives land.

## 4.8 Document Metadata (Head)

```dcz
@meta(
  title="Docz Spec — Block Directives",
  author="Docz Authors",
  description="Canonical examples for block directives in Docz",
  default_css="docz.core.css"
)
@end
```

## 4.9 Imports (Stylesheets and Assets)

```dcz
@import(href="/styles/site.css")
@end
```

> `@import(href="…")` → `<link rel="stylesheet" href="…">`.

## 4.10 Composition

Complex layout while keeping content readable:

```dcz
@style(class="prose")
# A Styled Section

@style(name="callout")
Remember: block directives compose. You can nest `@style` around `@code` or `@math`.
@end

@code(lang="bash")
zig build run -- run ./docs/SPEC.dcz
@end

@math
\text{Signal}(t) = A \cdot \sin(2\pi f t + \varphi)
@end
@end
```

## 4.11 Normalize to Explicit (optional)

```bash
docz convert input.dcz --explicit > canonical.dcz
```

## 4.12 Common Pitfalls

- Don’t use Markdown backticks for code; use `@code(lang="...")`.  
- Leave a blank line between paragraphs.  
- Put global aliases in a single `@style(mode="global")` block near the top.  
- KaTeX is display-only; to style inside math, use `\class{...}{...}`.

---

# 5. Inline Constructs

## 5.1 Emphasis, Strong, Code, Links

This is *emphasis*, this is **strong**, and this is `inline code`.  
Links: [Zig](https://ziglang.org).

## 5.2 Inline Math

- Newton's 2nd law: $F = ma$  
- Binomial: $(a+b)^2 = a^2 + 2ab + b^2$

> Use `@math ... @end` for display math.

## 5.3 Inline Styling with `@style`

- Tailwind/classes:
  `Energy is @style(class="font-semibold text-blue-600") important @end in physics.`
- Inline CSS:
  `@(style="color:#16a34a; text-decoration:underline"){success} vs. @(style="color:#dc2626"){failure}`

## 5.4 Interaction Hooks (HTML-like)

Attach `on-*` attributes (become `data-on-*` unless a runtime is present):

```dcz
@style(class="cursor-pointer underline" on-click="showNote('energy')")
Click for a quick note on energy
@end
```

## 5.5 Styling inside Math (KaTeX)

```dcz
@math
\class{varE}{E} = \class{varm}{m}\class{varc}{c}^{2}
@end

@css
.varE { color: #ca8a04; }   /* amber */
.varm { color: #16a34a; }   /* green */
.varc { color: #2563eb; }   /* blue  */
@end
```

---

# 6. Metadata, Imports & Head

- `@meta` → `<title>` / `<meta ...>`  
- `@import(href=...)` → `<link rel="stylesheet" ...>`  
- `@css ... @end` → concatenated `<style>` in `<head>`  
- `@style(mode="global")` → **aliases** for inline `@style`

(Examples already shown in §4.8–4.11.)

---

# 7. Styling & Themes

Three layers:

1) **Core CSS** — `docz.core.css` (always linked).  
2) **Your CSS** — via `@css` or user stylesheet.  
3) **Theme CSS (optional)** — Tailwind, if discovered.

Shorthand `@(...)` is equivalent to `@style(...) ... @end`.

Ordering:

1. `docz.core.css`  
2. user CSS (when `--css` is used)  
3. `docz.tailwind.css` (if present)  
4. inline `<style>` from `@css` blocks (in document order)

Accessibility:

- Prefer semantic HTML, ensure high contrast.  
- Preserve focus outlines for interactive spans.  
- Add ARIA roles when simulating controls with `@style`.

---

# 8. Interactivity & Actions

Two levels:

1. **Pure HTML/CSS** (`<details>`, focus/hover states).  
2. **Actions (`on-*`)** that can bind to JS or WASM handlers.

## 8.1 CSS-only

```dcz
@style(mode="global")
.button {
  display:inline-block; padding:0.5rem 0.9rem; border-radius:0.5rem;
  background:#111827; color:#fff; transition:transform .12s ease, filter .12s ease;
}
.button:hover { filter:brightness(1.1); }
.button:active { transform: translateY(1px) scale(0.99); }
@end

@style(class="button") Hover me — CSS only. @end
```

`<details>` is a great no-JS pattern:

```html
<details>
  <summary>More context (click to expand)</summary>
  This disclosure works without JavaScript or WASM.
</details>
```

## 8.2 Actions with `on-*`

```dcz
@style(class="button" on-click="sayHello") Click me @end
```

- **No runtime** → `<span class="button" data-on-click="sayHello">…</span>`  
- **Runtime present** → binds `click` to handler `sayHello` (JS or WASM export)

Supported attributes (pass-through): `class`, `style`, `id`, `role`, `tabindex`, any `aria-*`, and DOM-standard `on-*`.

## 8.3 Progressive enhancement (no WASM required)

```dcz
@style(class="button" id="pe-demo" on-click="togglePE") Toggle me (PE) @end
@style(id="pe-state") Current state: OFF @end

@code(lang="html")
<script>
  function togglePE(ev) {
    var s = document.getElementById('pe-state');
    s.textContent = s.textContent.includes('OFF') ? 'Current state: ON' : 'Current state: OFF';
  }
</script>
@end
```

## 8.4 WASM-bound handlers (shape)

Markup stays the same; handler names refer to **exported functions** in the active WASM module:

```dcz
@style(id="counter", class="font-mono") 0 @end
@style(class="button" on-click="inc") + @end
@style(class="button" on-click="dec") – @end
@style(class="button" on-click="reset") Reset @end

@code(lang="zig")
export fn inc() void { /* read #counter, ++, write back */ }
export fn dec() void { /* read #counter, --, write back */ }
export fn reset() void { /* set to 0 */ }
@end
```

> In the preview server, a tiny bridge auto-binds `data-on-*` to globals/WASM exports when available. In static HTML, they remain inert (progressive enhancement).

## 8.5 Security & Permissions

- Actions are inert without a runtime.  
- WASM runs sandboxed; no network/FS unless your host enables it.  
- Keep handlers idempotent and deterministic for portability.

---

# 9. WASM Execution Model

Docz supports WASM as an **optional** capability.

## 9.1 Enabling WASM (CLI)

```bash
docz enable wasm   # installs/links the minimal bridge the preview uses
docz preview       # hot-reload + auto-bind handlers when WASM exports are present
docz build file.dcz -o out.html
```

## 9.2 Supplying Modules

Two common patterns:

1) **External module** (linked by the host page or preview):

```dcz
@meta(wasm="/wasm/luma_core.wasm")   # host/runtime decides how to load/bind
@end
```

2) **Embedded descriptor** (for tools that inline):

```dcz
@wasm(name="luma", src="/wasm/luma_core.wasm", exports="inc,dec,reset")
@end
```

> Exact loading is host-dependent; Docz keeps the markup declarative.

## 9.3 Data Exchange

- Use DOM (`id=...`) as a rendezvous: read/write textContent, input values.  
- Prefer event-driven updates; avoid polling.  
- For larger data, pass JSON strings or shared buffers if your host supports it.

## 9.4 Determinism & Limits

- Keep execution deterministic for reproducibility.  
- Respect time/CPU caps in hosts (preview may throttle runaway loops).  
- Avoid nondeterministic APIs (Date.now/Math.random) unless justified.

---

# 10. Grammar (EBNF-style sketch)

```text
document      := (block | blank_line)*
block         := directive_block | heading | paragraph | html_block | code_block | math_block | style_block | css_block | import_stmt | media_block | meta_block
heading       := '#' heading_text | '##' heading_text | ... | '######' heading_text
paragraph     := (inline | text)+ blank_line
inline        := style_inline | emphasis | strong | code_inline | link | math_inline | text
directive_block
              := '@' ident attr_list? newline content '@end'
attr_list     := '(' attr (',' attr)* ')'
attr          := ident '=' string
style_inline  := '@(' attr_list_content ')' '{' text_inline+ '}'
```

> This sketch matches the examples; the reference parser defines exact tokenization.

---

# 11. CLI Reference (quick)

```text
docz preview [<path>] [--root <dir>] [--port <num>] [--no-open] [--config <file>]
docz build <file.dcz> [-o out.html]
docz convert <in.dcz> [--explicit] [--to html|markdown]
docz enable wasm
```

- `preview` serves docs with hot-reload and (optionally) action/WASM binding.  
- `build` writes a portable HTML file (CSS inlined by default).  
- `convert` normalizes to explicit form or targets other formats.

---

# 12. Reserved Names & Extension Points

- Core block directives: `@meta`, `@import`, `@css`, `@style`, `@code`, `@math`, `@media`, `@heading`.  
- Inline shorthand: `@(...) { ... }`.  
- Future-reserved: `@table`, `@figure`, `@ref`, `@bib`, `@wasm` (descriptor).  
- Custom directives should use a vendor prefix, e.g. `@x-luma-plot(...) ... @end`.

---

# 13. Versioning & Compatibility

- Files should declare a human version in `@meta(version="...")`.  
- Docz maintains **forward-compatible** parsing for stabilized constructs.  
- `docz convert --explicit` is the canonicalization step for CI/tools.

---

# 14. Testing Your Docs

- Unit tests near code (`test { ... }`) for renderers/parsers.  
- Integration: `zig build test-integration` for end-to-end HTML checks.  
- E2E: `zig build test-e2e` for CLI + preview flows.

---

# 15. Appendix A — Canonical `.dcz` (verbatim)

> See the top of this document for the fenced `.dcz` appendix that mirrors the spec examples one-to-one. Treat that as the source of truth for parsers and exporters.
