# DCZ File Specification — **Gold Verbatim Edition**
Version: 1.0.0 (Docz Public Preview)  
Status: Stable (Spec text), Reference-heavy (verbatim-appendix)  
Audience: Authors of `.dcz` documents, Docz tooling implementers, and plugin authors.

> This **Gold Verbatim Edition** is the *full, expanded* specification for DCZ (Docz)
> with verbose, near-verbatim demo blocks that mirror what a self-rendering `.dcz` might carry:
> long examples, repeated edge cases, CSS payloads, and WASM stubs.
> It is intentionally larger than the compact spec and is designed both as a **readable standard**
> and a **training corpus** for code assistants generating `.dcz` documents.

## 0. Design Goals (Recap)
- **Single-file documents** that compile to HTML by default; optional external CSS.
- **Deterministic inline transforms**: `\`code\``, `[links](url)`, *style spans* via `@style(...) … @end` or shorthand `@(...) { … }`.
- **Preserve math** markers like `$E = mc^2$` for KaTeX auto-render (do not consume `$...$` inline here).
- **Style Aliases** via `StyleDef` blocks: define `name → classes` mappings once; inline spans can use `name="..."` or `class="..."`.
- **Embeddable WASM** via `@wasm(...)` directive; pluggable directives allowed.
- **Security/escape rules**: escape HTML in code spans; encode attributes; conservative URL check for links.
- **Accessibility**: headings, alt text, captions, ARIA hints; keyboard-accessible interactions for `data-on-*` actions.

This edition expands each topic with **canonical rules + long-form, runnable-looking demos**.

## 1. DCZ Syntax Overview

A `.dcz` file is plain UTF-8 text. The primary constructs are:

### 1.1 Block nodes (top-level)
- `Heading(level=N)`: semantic titles. Example source form:
  ```
  # Level 1 Title
  ## Level 2
  ### Level 3
  ```
  Authors may also rely on an explicit parser output that provides `attributes.level`.

- `Content`: paragraphs with **inline** transformations:
  - Backticks for code: `` `const x = 3;` `` → `<code>const x = 3;</code>`
  - Markdown links: `[Zig](https://ziglang.org)` with a conservative URL check
  - Style spans: `@style(... ) … @end` or `@(…) { … }` (shorthand)
  - Inline math `$...$` is preserved for KaTeX auto-render (not consumed at this stage)

- `CodeBlock`: fenced code blocks; content is treated as pre-escaped.
- `Math`: block math (already parsed); will be rendered in math container.
- `Media`: images/video/audio; use attributes like `src`, `alt`, `title`, etc.
- `Style`: block-level styled container (uses class/alias resolution).
- `StyleDef`: define style aliases for inline and block use.
- `Import`: vendor asset hint (resolved by build/preview tooling).
- `Css`: inline CSS block to be emitted into `<style>` or bundled output.

### 1.2 Attributes
Attributes are key/value pairs. For inline **style spans**, the following keys are recognized:
- `name="alias"`: refers to a `StyleDef` alias → becomes `class="..."` with resolved class string.
- `class="..."` or `classes="..."`: explicit class list. If value **looks like CSS** (contains `:`, `;`, or `=`), it is treated as inline CSS.
- `style="..."`: explicit CSS declarations.
- Action-like attributes become `data-*`:
  - `on-click="..."` → `data-on-click="..."`
  - `on-hover="..."` → `data-on-hover="..."`
  - `on-focus="..."` → `data-on-focus="..."`

### 1.3 Escaping & Safety
- In code spans and attributes, escape `& < > " '`.  
- For URLs, use a conservative heuristic: must contain at least one letter and at least one of `. : /`.
- `$...$` is **not** interpreted by the inline rewriter; leave it intact for KaTeX/auto-render.

### 1.4 Style Alias Resolution (Inline/Block)
1. Build a map once: alias → classes (string).
2. For inline spans:
   - If `class`/`classes` is present and **looks like CSS**, treat it as inline `style` instead.
   - Else if `name` is present and resolves to alias, use `class="..."` with alias classes.
   - Merge `style` with any class-derived CSS only when `class` is judged to be CSS. Otherwise, class and style stay separate.
3. For block `Style`, prefer `classes` or fallback to alias via `name`.

## 2. Inline Transform Rules (Author-Facing)

### 2.1 Code Spans
- Syntax: `` `...` ``
- Escapes inside: allow `\`` and `\$` and `\\` by treating backslash as escape for those runes.
- Render as: `<code>…</code>` with HTML-escaped content.

**Example**
```
Use `std.heap.GeneralPurposeAllocator` when you need debugging features.
```

### 2.2 Links
- Syntax: `[text](url)`
- URL heuristic: must contain at least one letter and one of `. : /`.
- Render as: `<a href="...">text</a>` with attribute-safe escaping.

**Examples**
```
See [Zig](https://ziglang.org) and [Docs](https://ziglang.org/documentation/).
Bad: [oops](not_a_url) → left as literal text.
```

### 2.3 Style Spans
Two forms are accepted and **equivalent**:

**A. Explicit form**
```
@style(name="note", on-click="copy"){ Copy this! }
```
or
```
@style(class="rounded bg-yellow-50 px-2") nice note @end
```

**B. Shorthand form**
```
@(class="text-red-500 underline"){Danger}
```
or with `@end`:
```
@(style="color:red") highlight @end
```

Rules:
- If `class`/`classes` **looks like CSS** (contains `:`, `;`, or `=`), reinterpret as `style`.
  - E.g. `class="color = red"` → `style="color = red"`
- Merge multiple style sources; if both styles exist, join via `"; "`.

**Expected Rendering (examples)**
```
The @style(class="color = red") preview @end server.
→ The <span style="color = red">preview </span> server.
```
```
@(name="note"){Be mindful of allocator lifetime.}
→ <span class="rounded bg-yellow-50 px-2">Be mindful of allocator lifetime.</span>
```

### 2.4 Math `$...$` (preserved)
Inline math markers must remain verbatim for client-side auto-render:
```
Einstein: $E = mc^2$.
→ <p>Einstein: $E = mc^2$.</p>
```

## 3. Block Elements

### 3.1 Headings
- Hash-prefixed or parser-provided `attributes.level` (1–6). Render as `<hN>...</hN>`.

**Example**
```
# Title
## Section
### Subsection
```

### 3.2 Paragraphs (`Content`)
- A line or group of lines; apply inline rules to its text and wrap as `<p>…</p>`.

### 3.3 Code Blocks
- Fenced in source, or parser-specified. Treat content as already escaped (or escape once on write).

```
@code(lang="zig")
const std = @import("std");
@end
```

### 3.4 Math Blocks
- Put math in a container the client renderer recognizes.

```sh
$$
\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}
$$
```

### 3.5 Media
- Use attributes: `src`, `alt`, `title`, `width`, `height`. Render as `<img ...>` or appropriate tag.
- Provide **alt text** for accessibility.

### 3.6 Style (Block)
- Style a block via classes or alias:

```sh
@style(name="callout"){
This is a block callout with padding and background.
}
```
or

```sh
@style(classes="rounded bg-gray-50 p-4"){
Same effect, explicit classes.
}
```

### 3.7 StyleDef (Aliases)
- Define once per document; exporter builds a `alias → classes` map.
- Suggested inline format (Docz’s parser may accept others; the exporter just needs the map):

```sh
@styledef{
  note = "rounded bg-yellow-50 px-2"
  callout = "rounded-md border p-4 bg-blue-50"
  mathbox = "p-3 bg-gray-100 font-mono"
}
```

### 3.8 Import & Css
- `@import` records external asset hints; `@css` provides inline CSS to be emitted into `<style>`.

**Example**

```sh
@import{ src="/third_party/katex/0.16.22/dist/katex.min.css" }
@css{
  .docz-body { line-height: 1.55; }
}
```

## 4. WASM Embeds & Plugins

### 4.1 `@wasm` Directive (Author Surface)

- Minimal surface:

```sh
@wasm(
  src="wasm/zmath_demo.wasm",
  funcs="init, step, render",
  mount="#app-canvas",
  config="{ \"n\": 1024, \"dt\": 0.01 }"
){
  <canvas id="app-canvas" width="640" height="360" aria-label="Demo canvas"></canvas>
}
```

- The Docz runtime boots the module, passes `config`, wires events, and calls exported funcs as appropriate.

### 4.2 Plugin Hooks (Concept)
Docz supports a plugin system (e.g., to transform/import assets, inject head tags, verify third-party files).
At minimum, plugins may:
- Add validation on `@import` sources.
- Post-process inline spans (e.g., render shortcodes).
- Contribute CLI subcommands or “vendor” tasks.

## 5. Escaping, Safety, and Sanitization

- **Inline code**: Escape HTML, including quotes.
- **Attributes**: Escape with attribute-safe rules (`& < > " ' → entities`).
- **Style heuristic**: `class="color = red"` is **style** (contains `=`, `:`, or `;`). Normal class lists
  must not include those characters in ways that look like CSS.
- **Links**: Use a conservative URL check (has letters, has one of `. : /`). Leave suspicious forms literal.
- **Math**: Preserve `$...$`. Let client-side KaTeX process it safely.
- **Actions**: `on-click`, `on-hover`, `on-focus` become `data-*` only. No implicit JS execution.
- **WASM**: Only load from trusted origins. Provide integrity where possible (e.g., vendor checksum tooling).

## 6. Accessibility Guidelines

- **Headings**: Use levels in order (h1 → h2 → h3). Avoid skipping levels.
- **Alt text**: Every `Media` block should provide `alt` or an accessible alternative.
- **Contrast**: Style aliases must be mindful of contrast ratios (WCAG AA minimums).
- **Keyboard**: If you add `data-on-*` interaction, ensure focus styles and keyboard activation are supported.
- **Math**: Provide text alternatives or annotations where possible.
- **ARIA**: For complex widgets (e.g., WASM canvas with UI), add labels, roles, and live region hints as needed.

## 7. Implementation Contract (Exporter & Inline Rewriter)

- **Inline Rewriter** must perform, in order:
  1. Protect & escape **backtick code spans**.
  2. Rewrite **style spans** (`@style(...)` and `@(...)`) into `<span>` with class/style merge & `data-*` attrs.
  3. Rewrite **links** with conservative URL check.
  4. **Do not** consume `$...$` math markers.
- **HTML Exporter** must:
  - Build **style alias map** from `StyleDef` nodes before rendering body.
  - Render blocks as described (headings, paragraphs, code, math, media, style).
  - Optionally inject `<style>` from `Css` blocks at top (or return a separate CSS blob when requested).
  - Provide utilities used by CLI:
    - `collectInlineCss(doc)` → single CSS string (optional convenience).
    - `stripFirstStyleBlock(html)` → HTML without the first `<style>…</style>` (optional convenience).

## 8. Reference Payloads (Verbatim)

Below are **intentionally long** example payloads to mirror real documents.

### 8.1 Large Inline CSS Example
(As might appear in a `@css{...}` block or an extracted bundle.)

```css
.u-1 { padding:1px; margin:2px; border-radius:1px; }
.u-1-bg { background: hsl(7, 50%, 90%); }
.u-1-fg { color: hsl(11, 30%, 25%); }
.u-2 { padding:2px; margin:4px; border-radius:2px; }
.u-2-bg { background: hsl(14, 50%, 90%); }
.u-2-fg { color: hsl(22, 30%, 25%); }
.u-3 { padding:3px; margin:6px; border-radius:3px; }
.u-3-bg { background: hsl(21, 50%, 90%); }
.u-3-fg { color: hsl(33, 30%, 25%); }
.u-4 { padding:4px; margin:8px; border-radius:4px; }
.u-4-bg { background: hsl(28, 50%, 90%); }
.u-4-fg { color: hsl(44, 30%, 25%); }
.u-5 { padding:5px; margin:10px; border-radius:5px; }
.u-5-bg { background: hsl(35, 50%, 90%); }
.u-5-fg { color: hsl(55, 30%, 25%); }
.u-6 { padding:6px; margin:12px; border-radius:6px; }
.u-6-bg { background: hsl(42, 50%, 90%); }
.u-6-fg { color: hsl(66, 30%, 25%); }
.u-7 { padding:7px; margin:14px; border-radius:7px; }
.u-7-bg { background: hsl(49, 50%, 90%); }
.u-7-fg { color: hsl(77, 30%, 25%); }
.u-8 { padding:8px; margin:16px; border-radius:8px; }
.u-8-bg { background: hsl(56, 50%, 90%); }
.u-8-fg { color: hsl(88, 30%, 25%); }
.u-9 { padding:9px; margin:18px; border-radius:9px; }
.u-9-bg { background: hsl(63, 50%, 90%); }
.u-9-fg { color: hsl(99, 30%, 25%); }
.u-10 { padding:10px; margin:20px; border-radius:10px; }
.u-10-bg { background: hsl(70, 50%, 90%); }
.u-10-fg { color: hsl(110, 30%, 25%); }
.u-11 { padding:11px; margin:22px; border-radius:11px; }
.u-11-bg { background: hsl(77, 50%, 90%); }
.u-11-fg { color: hsl(121, 30%, 25%); }
.u-12 { padding:12px; margin:0px; border-radius:0px; }
.u-12-bg { background: hsl(84, 50%, 90%); }
.u-12-fg { color: hsl(132, 30%, 25%); }
.u-13 { padding:13px; margin:2px; border-radius:1px; }
.u-13-bg { background: hsl(91, 50%, 90%); }
.u-13-fg { color: hsl(143, 30%, 25%); }
.u-14 { padding:14px; margin:4px; border-radius:2px; }
.u-14-bg { background: hsl(98, 50%, 90%); }
.u-14-fg { color: hsl(154, 30%, 25%); }
.u-15 { padding:15px; margin:6px; border-radius:3px; }
.u-15-bg { background: hsl(105, 50%, 90%); }
.u-15-fg { color: hsl(165, 30%, 25%); }
.u-16 { padding:0px; margin:8px; border-radius:4px; }
.u-16-bg { background: hsl(112, 50%, 90%); }
.u-16-fg { color: hsl(176, 30%, 25%); }
.u-17 { padding:1px; margin:10px; border-radius:5px; }
.u-17-bg { background: hsl(119, 50%, 90%); }
.u-17-fg { color: hsl(187, 30%, 25%); }
.u-18 { padding:2px; margin:12px; border-radius:6px; }
.u-18-bg { background: hsl(126, 50%, 90%); }
.u-18-fg { color: hsl(198, 30%, 25%); }
.u-19 { padding:3px; margin:14px; border-radius:7px; }
.u-19-bg { background: hsl(133, 50%, 90%); }
.u-19-fg { color: hsl(209, 30%, 25%); }
.u-20 { padding:4px; margin:16px; border-radius:8px; }
.u-20-bg { background: hsl(140, 50%, 90%); }
.u-20-fg { color: hsl(220, 30%, 25%); }
.u-21 { padding:5px; margin:18px; border-radius:9px; }
.u-21-bg { background: hsl(147, 50%, 90%); }
.u-21-fg { color: hsl(231, 30%, 25%); }
.u-22 { padding:6px; margin:20px; border-radius:10px; }
.u-22-bg { background: hsl(154, 50%, 90%); }
.u-22-fg { color: hsl(242, 30%, 25%); }
.u-23 { padding:7px; margin:22px; border-radius:11px; }
.u-23-bg { background: hsl(161, 50%, 90%); }
.u-23-fg { color: hsl(253, 30%, 25%); }
.u-24 { padding:8px; margin:0px; border-radius:0px; }
.u-24-bg { background: hsl(168, 50%, 90%); }
.u-24-fg { color: hsl(264, 30%, 25%); }
.u-25 { padding:9px; margin:2px; border-radius:1px; }
.u-25-bg { background: hsl(175, 50%, 90%); }
.u-25-fg { color: hsl(275, 30%, 25%); }
.u-26 { padding:10px; margin:4px; border-radius:2px; }
.u-26-bg { background: hsl(182, 50%, 90%); }
.u-26-fg { color: hsl(286, 30%, 25%); }
.u-27 { padding:11px; margin:6px; border-radius:3px; }
.u-27-bg { background: hsl(189, 50%, 90%); }
.u-27-fg { color: hsl(297, 30%, 25%); }
.u-28 { padding:12px; margin:8px; border-radius:4px; }
.u-28-bg { background: hsl(196, 50%, 90%); }
.u-28-fg { color: hsl(308, 30%, 25%); }
.u-29 { padding:13px; margin:10px; border-radius:5px; }
.u-29-bg { background: hsl(203, 50%, 90%); }
.u-29-fg { color: hsl(319, 30%, 25%); }
.u-30 { padding:14px; margin:12px; border-radius:6px; }
.u-30-bg { background: hsl(210, 50%, 90%); }
.u-30-fg { color: hsl(330, 30%, 25%); }
.u-31 { padding:15px; margin:14px; border-radius:7px; }
.u-31-bg { background: hsl(217, 50%, 90%); }
.u-31-fg { color: hsl(341, 30%, 25%); }
.u-32 { padding:0px; margin:16px; border-radius:8px; }
.u-32-bg { background: hsl(224, 50%, 90%); }
.u-32-fg { color: hsl(352, 30%, 25%); }
.u-33 { padding:1px; margin:18px; border-radius:9px; }
.u-33-bg { background: hsl(231, 50%, 90%); }
.u-33-fg { color: hsl(3, 30%, 25%); }
.u-34 { padding:2px; margin:20px; border-radius:10px; }
.u-34-bg { background: hsl(238, 50%, 90%); }
.u-34-fg { color: hsl(14, 30%, 25%); }
.u-35 { padding:3px; margin:22px; border-radius:11px; }
.u-35-bg { background: hsl(245, 50%, 90%); }
.u-35-fg { color: hsl(25, 30%, 25%); }
.u-36 { padding:4px; margin:0px; border-radius:0px; }
.u-36-bg { background: hsl(252, 50%, 90%); }
.u-36-fg { color: hsl(36, 30%, 25%); }
.u-37 { padding:5px; margin:2px; border-radius:1px; }
.u-37-bg { background: hsl(259, 50%, 90%); }
.u-37-fg { color: hsl(47, 30%, 25%); }
.u-38 { padding:6px; margin:4px; border-radius:2px; }
.u-38-bg { background: hsl(266, 50%, 90%); }
.u-38-fg { color: hsl(58, 30%, 25%); }
.u-39 { padding:7px; margin:6px; border-radius:3px; }
.u-39-bg { background: hsl(273, 50%, 90%); }
.u-39-fg { color: hsl(69, 30%, 25%); }
.u-40 { padding:8px; margin:8px; border-radius:4px; }
.u-40-bg { background: hsl(280, 50%, 90%); }
.u-40-fg { color: hsl(80, 30%, 25%); }
.u-41 { padding:9px; margin:10px; border-radius:5px; }
.u-41-bg { background: hsl(287, 50%, 90%); }
.u-41-fg { color: hsl(91, 30%, 25%); }
.u-42 { padding:10px; margin:12px; border-radius:6px; }
.u-42-bg { background: hsl(294, 50%, 90%); }
.u-42-fg { color: hsl(102, 30%, 25%); }
.u-43 { padding:11px; margin:14px; border-radius:7px; }
.u-43-bg { background: hsl(301, 50%, 90%); }
.u-43-fg { color: hsl(113, 30%, 25%); }
.u-44 { padding:12px; margin:16px; border-radius:8px; }
.u-44-bg { background: hsl(308, 50%, 90%); }
.u-44-fg { color: hsl(124, 30%, 25%); }
.u-45 { padding:13px; margin:18px; border-radius:9px; }
.u-45-bg { background: hsl(315, 50%, 90%); }
.u-45-fg { color: hsl(135, 30%, 25%); }
.u-46 { padding:14px; margin:20px; border-radius:10px; }
.u-46-bg { background: hsl(322, 50%, 90%); }
.u-46-fg { color: hsl(146, 30%, 25%); }
.u-47 { padding:15px; margin:22px; border-radius:11px; }
.u-47-bg { background: hsl(329, 50%, 90%); }
.u-47-fg { color: hsl(157, 30%, 25%); }
.u-48 { padding:0px; margin:0px; border-radius:0px; }
.u-48-bg { background: hsl(336, 50%, 90%); }
.u-48-fg { color: hsl(168, 30%, 25%); }
.u-49 { padding:1px; margin:2px; border-radius:1px; }
.u-49-bg { background: hsl(343, 50%, 90%); }
.u-49-fg { color: hsl(179, 30%, 25%); }
.u-50 { padding:2px; margin:4px; border-radius:2px; }
.u-50-bg { background: hsl(350, 50%, 90%); }
.u-50-fg { color: hsl(190, 30%, 25%); }
.u-51 { padding:3px; margin:6px; border-radius:3px; }
.u-51-bg { background: hsl(357, 50%, 90%); }
.u-51-fg { color: hsl(201, 30%, 25%); }
.u-52 { padding:4px; margin:8px; border-radius:4px; }
.u-52-bg { background: hsl(4, 50%, 90%); }
.u-52-fg { color: hsl(212, 30%, 25%); }
.u-53 { padding:5px; margin:10px; border-radius:5px; }
.u-53-bg { background: hsl(11, 50%, 90%); }
.u-53-fg { color: hsl(223, 30%, 25%); }
.u-54 { padding:6px; margin:12px; border-radius:6px; }
.u-54-bg { background: hsl(18, 50%, 90%); }
.u-54-fg { color: hsl(234, 30%, 25%); }
.u-55 { padding:7px; margin:14px; border-radius:7px; }
.u-55-bg { background: hsl(25, 50%, 90%); }
.u-55-fg { color: hsl(245, 30%, 25%); }
.u-56 { padding:8px; margin:16px; border-radius:8px; }
.u-56-bg { background: hsl(32, 50%, 90%); }
.u-56-fg { color: hsl(256, 30%, 25%); }
.u-57 { padding:9px; margin:18px; border-radius:9px; }
.u-57-bg { background: hsl(39, 50%, 90%); }
.u-57-fg { color: hsl(267, 30%, 25%); }
.u-58 { padding:10px; margin:20px; border-radius:10px; }
.u-58-bg { background: hsl(46, 50%, 90%); }
.u-58-fg { color: hsl(278, 30%, 25%); }
.u-59 { padding:11px; margin:22px; border-radius:11px; }
.u-59-bg { background: hsl(53, 50%, 90%); }
.u-59-fg { color: hsl(289, 30%, 25%); }
.u-60 { padding:12px; margin:0px; border-radius:0px; }
.u-60-bg { background: hsl(60, 50%, 90%); }
.u-60-fg { color: hsl(300, 30%, 25%); }
.u-61 { padding:13px; margin:2px; border-radius:1px; }
.u-61-bg { background: hsl(67, 50%, 90%); }
.u-61-fg { color: hsl(311, 30%, 25%); }
.u-62 { padding:14px; margin:4px; border-radius:2px; }
.u-62-bg { background: hsl(74, 50%, 90%); }
.u-62-fg { color: hsl(322, 30%, 25%); }
.u-63 { padding:15px; margin:6px; border-radius:3px; }
.u-63-bg { background: hsl(81, 50%, 90%); }
.u-63-fg { color: hsl(333, 30%, 25%); }
.u-64 { padding:0px; margin:8px; border-radius:4px; }
.u-64-bg { background: hsl(88, 50%, 90%); }
.u-64-fg { color: hsl(344, 30%, 25%); }
.u-65 { padding:1px; margin:10px; border-radius:5px; }
.u-65-bg { background: hsl(95, 50%, 90%); }
.u-65-fg { color: hsl(355, 30%, 25%); }
.u-66 { padding:2px; margin:12px; border-radius:6px; }
.u-66-bg { background: hsl(102, 50%, 90%); }
.u-66-fg { color: hsl(6, 30%, 25%); }
.u-67 { padding:3px; margin:14px; border-radius:7px; }
.u-67-bg { background: hsl(109, 50%, 90%); }
.u-67-fg { color: hsl(17, 30%, 25%); }
.u-68 { padding:4px; margin:16px; border-radius:8px; }
.u-68-bg { background: hsl(116, 50%, 90%); }
.u-68-fg { color: hsl(28, 30%, 25%); }
.u-69 { padding:5px; margin:18px; border-radius:9px; }
.u-69-bg { background: hsl(123, 50%, 90%); }
.u-69-fg { color: hsl(39, 30%, 25%); }
.u-70 { padding:6px; margin:20px; border-radius:10px; }
.u-70-bg { background: hsl(130, 50%, 90%); }
.u-70-fg { color: hsl(50, 30%, 25%); }
.u-71 { padding:7px; margin:22px; border-radius:11px; }
.u-71-bg { background: hsl(137, 50%, 90%); }
.u-71-fg { color: hsl(61, 30%, 25%); }
.u-72 { padding:8px; margin:0px; border-radius:0px; }
.u-72-bg { background: hsl(144, 50%, 90%); }
.u-72-fg { color: hsl(72, 30%, 25%); }
.u-73 { padding:9px; margin:2px; border-radius:1px; }
.u-73-bg { background: hsl(151, 50%, 90%); }
.u-73-fg { color: hsl(83, 30%, 25%); }
.u-74 { padding:10px; margin:4px; border-radius:2px; }
.u-74-bg { background: hsl(158, 50%, 90%); }
.u-74-fg { color: hsl(94, 30%, 25%); }
.u-75 { padding:11px; margin:6px; border-radius:3px; }
.u-75-bg { background: hsl(165, 50%, 90%); }
.u-75-fg { color: hsl(105, 30%, 25%); }
.u-76 { padding:12px; margin:8px; border-radius:4px; }
.u-76-bg { background: hsl(172, 50%, 90%); }
.u-76-fg { color: hsl(116, 30%, 25%); }
.u-77 { padding:13px; margin:10px; border-radius:5px; }
.u-77-bg { background: hsl(179, 50%, 90%); }
.u-77-fg { color: hsl(127, 30%, 25%); }
.u-78 { padding:14px; margin:12px; border-radius:6px; }
.u-78-bg { background: hsl(186, 50%, 90%); }
.u-78-fg { color: hsl(138, 30%, 25%); }
.u-79 { padding:15px; margin:14px; border-radius:7px; }
.u-79-bg { background: hsl(193, 50%, 90%); }
.u-79-fg { color: hsl(149, 30%, 25%); }
.u-80 { padding:0px; margin:16px; border-radius:8px; }
.u-80-bg { background: hsl(200, 50%, 90%); }
.u-80-fg { color: hsl(160, 30%, 25%); }
.u-81 { padding:1px; margin:18px; border-radius:9px; }
.u-81-bg { background: hsl(207, 50%, 90%); }
.u-81-fg { color: hsl(171, 30%, 25%); }
.u-82 { padding:2px; margin:20px; border-radius:10px; }
.u-82-bg { background: hsl(214, 50%, 90%); }
.u-82-fg { color: hsl(182, 30%, 25%); }
.u-83 { padding:3px; margin:22px; border-radius:11px; }
.u-83-bg { background: hsl(221, 50%, 90%); }
.u-83-fg { color: hsl(193, 30%, 25%); }
.u-84 { padding:4px; margin:0px; border-radius:0px; }
.u-84-bg { background: hsl(228, 50%, 90%); }
.u-84-fg { color: hsl(204, 30%, 25%); }
.u-85 { padding:5px; margin:2px; border-radius:1px; }
.u-85-bg { background: hsl(235, 50%, 90%); }
.u-85-fg { color: hsl(215, 30%, 25%); }
.u-86 { padding:6px; margin:4px; border-radius:2px; }
.u-86-bg { background: hsl(242, 50%, 90%); }
.u-86-fg { color: hsl(226, 30%, 25%); }
.u-87 { padding:7px; margin:6px; border-radius:3px; }
.u-87-bg { background: hsl(249, 50%, 90%); }
.u-87-fg { color: hsl(237, 30%, 25%); }
.u-88 { padding:8px; margin:8px; border-radius:4px; }
.u-88-bg { background: hsl(256, 50%, 90%); }
.u-88-fg { color: hsl(248, 30%, 25%); }
.u-89 { padding:9px; margin:10px; border-radius:5px; }
.u-89-bg { background: hsl(263, 50%, 90%); }
.u-89-fg { color: hsl(259, 30%, 25%); }
.u-90 { padding:10px; margin:12px; border-radius:6px; }
.u-90-bg { background: hsl(270, 50%, 90%); }
.u-90-fg { color: hsl(270, 30%, 25%); }
.u-91 { padding:11px; margin:14px; border-radius:7px; }
.u-91-bg { background: hsl(277, 50%, 90%); }
.u-91-fg { color: hsl(281, 30%, 25%); }
.u-92 { padding:12px; margin:16px; border-radius:8px; }
.u-92-bg { background: hsl(284, 50%, 90%); }
.u-92-fg { color: hsl(292, 30%, 25%); }
.u-93 { padding:13px; margin:18px; border-radius:9px; }
.u-93-bg { background: hsl(291, 50%, 90%); }
.u-93-fg { color: hsl(303, 30%, 25%); }
.u-94 { padding:14px; margin:20px; border-radius:10px; }
.u-94-bg { background: hsl(298, 50%, 90%); }
.u-94-fg { color: hsl(314, 30%, 25%); }
.u-95 { padding:15px; margin:22px; border-radius:11px; }
.u-95-bg { background: hsl(305, 50%, 90%); }
.u-95-fg { color: hsl(325, 30%, 25%); }
.u-96 { padding:0px; margin:0px; border-radius:0px; }
.u-96-bg { background: hsl(312, 50%, 90%); }
.u-96-fg { color: hsl(336, 30%, 25%); }
.u-97 { padding:1px; margin:2px; border-radius:1px; }
.u-97-bg { background: hsl(319, 50%, 90%); }
.u-97-fg { color: hsl(347, 30%, 25%); }
.u-98 { padding:2px; margin:4px; border-radius:2px; }
.u-98-bg { background: hsl(326, 50%, 90%); }
.u-98-fg { color: hsl(358, 30%, 25%); }
.u-99 { padding:3px; margin:6px; border-radius:3px; }
.u-99-bg { background: hsl(333, 50%, 90%); }
.u-99-fg { color: hsl(9, 30%, 25%); }
.u-100 { padding:4px; margin:8px; border-radius:4px; }
.u-100-bg { background: hsl(340, 50%, 90%); }
.u-100-fg { color: hsl(20, 30%, 25%); }
.u-101 { padding:5px; margin:10px; border-radius:5px; }
.u-101-bg { background: hsl(347, 50%, 90%); }
.u-101-fg { color: hsl(31, 30%, 25%); }
.u-102 { padding:6px; margin:12px; border-radius:6px; }
.u-102-bg { background: hsl(354, 50%, 90%); }
.u-102-fg { color: hsl(42, 30%, 25%); }
.u-103 { padding:7px; margin:14px; border-radius:7px; }
.u-103-bg { background: hsl(1, 50%, 90%); }
.u-103-fg { color: hsl(53, 30%, 25%); }
.u-104 { padding:8px; margin:16px; border-radius:8px; }
.u-104-bg { background: hsl(8, 50%, 90%); }
.u-104-fg { color: hsl(64, 30%, 25%); }
.u-105 { padding:9px; margin:18px; border-radius:9px; }
.u-105-bg { background: hsl(15, 50%, 90%); }
.u-105-fg { color: hsl(75, 30%, 25%); }
.u-106 { padding:10px; margin:20px; border-radius:10px; }
.u-106-bg { background: hsl(22, 50%, 90%); }
.u-106-fg { color: hsl(86, 30%, 25%); }
.u-107 { padding:11px; margin:22px; border-radius:11px; }
.u-107-bg { background: hsl(29, 50%, 90%); }
.u-107-fg { color: hsl(97, 30%, 25%); }
.u-108 { padding:12px; margin:0px; border-radius:0px; }
.u-108-bg { background: hsl(36, 50%, 90%); }
.u-108-fg { color: hsl(108, 30%, 25%); }
.u-109 { padding:13px; margin:2px; border-radius:1px; }
.u-109-bg { background: hsl(43, 50%, 90%); }
.u-109-fg { color: hsl(119, 30%, 25%); }
.u-110 { padding:14px; margin:4px; border-radius:2px; }
.u-110-bg { background: hsl(50, 50%, 90%); }
.u-110-fg { color: hsl(130, 30%, 25%); }
.u-111 { padding:15px; margin:6px; border-radius:3px; }
.u-111-bg { background: hsl(57, 50%, 90%); }
.u-111-fg { color: hsl(141, 30%, 25%); }
.u-112 { padding:0px; margin:8px; border-radius:4px; }
.u-112-bg { background: hsl(64, 50%, 90%); }
.u-112-fg { color: hsl(152, 30%, 25%); }
.u-113 { padding:1px; margin:10px; border-radius:5px; }
.u-113-bg { background: hsl(71, 50%, 90%); }
.u-113-fg { color: hsl(163, 30%, 25%); }
.u-114 { padding:2px; margin:12px; border-radius:6px; }
.u-114-bg { background: hsl(78, 50%, 90%); }
.u-114-fg { color: hsl(174, 30%, 25%); }
.u-115 { padding:3px; margin:14px; border-radius:7px; }
.u-115-bg { background: hsl(85, 50%, 90%); }
.u-115-fg { color: hsl(185, 30%, 25%); }
.u-116 { padding:4px; margin:16px; border-radius:8px; }
.u-116-bg { background: hsl(92, 50%, 90%); }
.u-116-fg { color: hsl(196, 30%, 25%); }
.u-117 { padding:5px; margin:18px; border-radius:9px; }
.u-117-bg { background: hsl(99, 50%, 90%); }
```

```dcz
@css{
.u-1 { padding:1px; margin:2px; border-radius:1px; }
.u-1-bg { background: hsl(7, 50%, 90%); }
.u-1-fg { color: hsl(11, 30%, 25%); }
.u-2 { padding:2px; margin:4px; border-radius:2px; }
.u-2-bg { background: hsl(14, 50%, 90%); }
.u-2-fg { color: hsl(22, 30%, 25%); }
.u-3 { padding:3px; margin:6px; border-radius:3px; }
.u-3-bg { background: hsl(21, 50%, 90%); }
.u-3-fg { color: hsl(33, 30%, 25%); }
.u-4 { padding:4px; margin:8px; border-radius:4px; }
.u-4-bg { background: hsl(28, 50%, 90%); }
.u-4-fg { color: hsl(44, 30%, 25%); }
.u-5 { padding:5px; margin:10px; border-radius:5px; }
.u-5-bg { background: hsl(35, 50%, 90%); }
.u-5-fg { color: hsl(55, 30%, 25%); }
.u-6 { padding:6px; margin:12px; border-radius:6px; }
.u-6-bg { background: hsl(42, 50%, 90%); }
.u-6-fg { color: hsl(66, 30%, 25%); }
.u-7 { padding:7px; margin:14px; border-radius:7px; }
.u-7-bg { background: hsl(49, 50%, 90%); }
.u-7-fg { color: hsl(77, 30%, 25%); }
.u-8 { padding:8px; margin:16px; border-radius:8px; }
.u-8-bg { background: hsl(56, 50%, 90%); }
.u-8-fg { color: hsl(88, 30%, 25%); }
.u-9 { padding:9px; margin:18px; border-radius:9px; }
.u-9-bg { background: hsl(63, 50%, 90%); }
.u-9-fg { color: hsl(99, 30%, 25%); }
.u-10 { padding:10px; margin:20px; border-radius:10px; }
.u-10-bg { background: hsl(70, 50%, 90%); }
.u-10-fg { color: hsl(110, 30%, 25%); }
.u-11 { padding:11px; margin:22px; border-radius:11px; }
.u-11-bg { background: hsl(77, 50%, 90%); }
.u-11-fg { color: hsl(121, 30%, 25%); }
.u-12 { padding:12px; margin:0px; border-radius:0px; }
.u-12-bg { background: hsl(84, 50%, 90%); }
.u-12-fg { color: hsl(132, 30%, 25%); }
.u-13 { padding:13px; margin:2px; border-radius:1px; }
.u-13-bg { background: hsl(91, 50%, 90%); }
.u-13-fg { color: hsl(143, 30%, 25%); }
.u-14 { padding:14px; margin:4px; border-radius:2px; }
.u-14-bg { background: hsl(98, 50%, 90%); }
.u-14-fg { color: hsl(154, 30%, 25%); }
.u-15 { padding:15px; margin:6px; border-radius:3px; }
.u-15-bg { background: hsl(105, 50%, 90%); }
.u-15-fg { color: hsl(165, 30%, 25%); }
.u-16 { padding:0px; margin:8px; border-radius:4px; }
.u-16-bg { background: hsl(112, 50%, 90%); }
.u-16-fg { color: hsl(176, 30%, 25%); }
.u-17 { padding:1px; margin:10px; border-radius:5px; }
.u-17-bg { background: hsl(119, 50%, 90%); }
.u-17-fg { color: hsl(187, 30%, 25%); }
.u-18 { padding:2px; margin:12px; border-radius:6px; }
.u-18-bg { background: hsl(126, 50%, 90%); }
.u-18-fg { color: hsl(198, 30%, 25%); }
.u-19 { padding:3px; margin:14px; border-radius:7px; }
.u-19-bg { background: hsl(133, 50%, 90%); }
.u-19-fg { color: hsl(209, 30%, 25%); }
.u-20 { padding:4px; margin:16px; border-radius:8px; }
.u-20-bg { background: hsl(140, 50%, 90%); }
.u-20-fg { color: hsl(220, 30%, 25%); }
.u-21 { padding:5px; margin:18px; border-radius:9px; }
.u-21-bg { background: hsl(147, 50%, 90%); }
.u-21-fg { color: hsl(231, 30%, 25%); }
.u-22 { padding:6px; margin:20px; border-radius:10px; }
.u-22-bg { background: hsl(154, 50%, 90%); }
.u-22-fg { color: hsl(242, 30%, 25%); }
.u-23 { padding:7px; margin:22px; border-radius:11px; }
.u-23-bg { background: hsl(161, 50%, 90%); }
.u-23-fg { color: hsl(253, 30%, 25%); }
.u-24 { padding:8px; margin:0px; border-radius:0px; }
.u-24-bg { background: hsl(168, 50%, 90%); }
.u-24-fg { color: hsl(264, 30%, 25%); }
.u-25 { padding:9px; margin:2px; border-radius:1px; }
.u-25-bg { background: hsl(175, 50%, 90%); }
.u-25-fg { color: hsl(275, 30%, 25%); }
.u-26 { padding:10px; margin:4px; border-radius:2px; }
.u-26-bg { background: hsl(182, 50%, 90%); }
.u-26-fg { color: hsl(286, 30%, 25%); }
.u-27 { padding:11px; margin:6px; border-radius:3px; }
.u-27-bg { background: hsl(189, 50%, 90%); }
.u-27-fg { color: hsl(297, 30%, 25%); }
.u-28 { padding:12px; margin:8px; border-radius:4px; }
.u-28-bg { background: hsl(196, 50%, 90%); }
.u-28-fg { color: hsl(308, 30%, 25%); }
.u-29 { padding:13px; margin:10px; border-radius:5px; }
.u-29-bg { background: hsl(203, 50%, 90%); }
.u-29-fg { color: hsl(319, 30%, 25%); }
.u-30 { padding:14px; margin:12px; border-radius:6px; }
.u-30-bg { background: hsl(210, 50%, 90%); }
.u-30-fg { color: hsl(330, 30%, 25%); }
.u-31 { padding:15px; margin:14px; border-radius:7px; }
.u-31-bg { background: hsl(217, 50%, 90%); }
.u-31-fg { color: hsl(341, 30%, 25%); }
.u-32 { padding:0px; margin:16px; border-radius:8px; }
.u-32-bg { background: hsl(224, 50%, 90%); }
.u-32-fg { color: hsl(352, 30%, 25%); }
.u-33 { padding:1px; margin:18px; border-radius:9px; }
.u-33-bg { background: hsl(231, 50%, 90%); }
.u-33-fg { color: hsl(3, 30%, 25%); }
.u-34 { padding:2px; margin:20px; border-radius:10px; }
.u-34-bg { background: hsl(238, 50%, 90%); }
.u-34-fg { color: hsl(14, 30%, 25%); }
.u-35 { padding:3px; margin:22px; border-radius:11px; }
.u-35-bg { background: hsl(245, 50%, 90%); }
.u-35-fg { color: hsl(25, 30%, 25%); }
.u-36 { padding:4px; margin:0px; border-radius:0px; }
.u-36-bg { background: hsl(252, 50%, 90%); }
.u-36-fg { color: hsl(36, 30%, 25%); }
.u-37 { padding:5px; margin:2px; border-radius:1px; }
.u-37-bg { background: hsl(259, 50%, 90%); }
.u-37-fg { color: hsl(47, 30%, 25%); }
.u-38 { padding:6px; margin:4px; border-radius:2px; }
.u-38-bg { background: hsl(266, 50%, 90%); }
.u-38-fg { color: hsl(58, 30%, 25%); }
.u-39 { padding:7px; margin:6px; border-radius:3px; }
.u-39-bg { background: hsl(273, 50%, 90%); }
.u-39-fg { color: hsl(69, 30%, 25%); }
.u-40 { padding:8px; margin:8px; border-radius:4px; }
.u-40-bg { background: hsl(280, 50%, 90%); }
.u-40-fg { color: hsl(80, 30%, 25%); }
.u-41 { padding:9px; margin:10px; border-radius:5px; }
.u-41-bg { background: hsl(287, 50%, 90%); }
.u-41-fg { color: hsl(91, 30%, 25%); }
.u-42 { padding:10px; margin:12px; border-radius:6px; }
.u-42-bg { background: hsl(294, 50%, 90%); }
.u-42-fg { color: hsl(102, 30%, 25%); }
.u-43 { padding:11px; margin:14px; border-radius:7px; }
.u-43-bg { background: hsl(301, 50%, 90%); }
.u-43-fg { color: hsl(113, 30%, 25%); }
.u-44 { padding:12px; margin:16px; border-radius:8px; }
.u-44-bg { background: hsl(308, 50%, 90%); }
.u-44-fg { color: hsl(124, 30%, 25%); }
.u-45 { padding:13px; margin:18px; border-radius:9px; }
.u-45-bg { background: hsl(315, 50%, 90%); }
.u-45-fg { color: hsl(135, 30%, 25%); }
.u-46 { padding:14px; margin:20px; border-radius:10px; }
.u-46-bg { background: hsl(322, 50%, 90%); }
.u-46-fg { color: hsl(146, 30%, 25%); }
.u-47 { padding:15px; margin:22px; border-radius:11px; }
.u-47-bg { background: hsl(329, 50%, 90%); }
.u-47-fg { color: hsl(157, 30%, 25%); }
.u-48 { padding:0px; margin:0px; border-radius:0px; }
.u-48-bg { background: hsl(336, 50%, 90%); }
.u-48-fg { color: hsl(168, 30%, 25%); }
.u-49 { padding:1px; margin:2px; border-radius:1px; }
.u-49-bg { background: hsl(343, 50%, 90%); }
.u-49-fg { color: hsl(179, 30%, 25%); }
.u-50 { padding:2px; margin:4px; border-radius:2px; }
.u-50-bg { background: hsl(350, 50%, 90%); }
.u-50-fg { color: hsl(190, 30%, 25%); }
.u-51 { padding:3px; margin:6px; border-radius:3px; }
.u-51-bg { background: hsl(357, 50%, 90%); }
.u-51-fg { color: hsl(201, 30%, 25%); }
.u-52 { padding:4px; margin:8px; border-radius:4px; }
.u-52-bg { background: hsl(4, 50%, 90%); }
.u-52-fg { color: hsl(212, 30%, 25%); }
.u-53 { padding:5px; margin:10px; border-radius:5px; }
.u-53-bg { background: hsl(11, 50%, 90%); }
.u-53-fg { color: hsl(223, 30%, 25%); }
.u-54 { padding:6px; margin:12px; border-radius:6px; }
.u-54-bg { background: hsl(18, 50%, 90%); }
.u-54-fg { color: hsl(234, 30%, 25%); }
.u-55 { padding:7px; margin:14px; border-radius:7px; }
.u-55-bg { background: hsl(25, 50%, 90%); }
.u-55-fg { color: hsl(245, 30%, 25%); }
.u-56 { padding:8px; margin:16px; border-radius:8px; }
.u-56-bg { background: hsl(32, 50%, 90%); }
.u-56-fg { color: hsl(256, 30%, 25%); }
.u-57 { padding:9px; margin:18px; border-radius:9px; }
.u-57-bg { background: hsl(39, 50%, 90%); }
.u-57-fg { color: hsl(267, 30%, 25%); }
.u-58 { padding:10px; margin:20px; border-radius:10px; }
.u-58-bg { background: hsl(46, 50%, 90%); }
.u-58-fg { color: hsl(278, 30%, 25%); }
.u-59 { padding:11px; margin:22px; border-radius:11px; }
.u-59-bg { background: hsl(53, 50%, 90%); }
.u-59-fg { color: hsl(289, 30%, 25%); }
.u-60 { padding:12px; margin:0px; border-radius:0px; }
.u-60-bg { background: hsl(60, 50%, 90%); }
.u-60-fg { color: hsl(300, 30%, 25%); }
.u-61 { padding:13px; margin:2px; border-radius:1px; }
.u-61-bg { background: hsl(67, 50%, 90%); }
.u-61-fg { color: hsl(311, 30%, 25%); }
.u-62 { padding:14px; margin:4px; border-radius:2px; }
.u-62-bg { background: hsl(74, 50%, 90%); }
.u-62-fg { color: hsl(322, 30%, 25%); }
.u-63 { padding:15px; margin:6px; border-radius:3px; }
.u-63-bg { background: hsl(81, 50%, 90%); }
.u-63-fg { color: hsl(333, 30%, 25%); }
.u-64 { padding:0px; margin:8px; border-radius:4px; }
.u-64-bg { background: hsl(88, 50%, 90%); }
.u-64-fg { color: hsl(344, 30%, 25%); }
.u-65 { padding:1px; margin:10px; border-radius:5px; }
.u-65-bg { background: hsl(95, 50%, 90%); }
.u-65-fg { color: hsl(355, 30%, 25%); }
.u-66 { padding:2px; margin:12px; border-radius:6px; }
.u-66-bg { background: hsl(102, 50%, 90%); }
.u-66-fg { color: hsl(6, 30%, 25%); }
.u-67 { padding:3px; margin:14px; border-radius:7px; }
.u-67-bg { background: hsl(109, 50%, 90%); }
.u-67-fg { color: hsl(17, 30%, 25%); }
.u-68 { padding:4px; margin:16px; border-radius:8px; }
.u-68-bg { background: hsl(116, 50%, 90%); }
.u-68-fg { color: hsl(28, 30%, 25%); }
.u-69 { padding:5px; margin:18px; border-radius:9px; }
.u-69-bg { background: hsl(123, 50%, 90%); }
.u-69-fg { color: hsl(39, 30%, 25%); }
.u-70 { padding:6px; margin:20px; border-radius:10px; }
.u-70-bg { background: hsl(130, 50%, 90%); }
.u-70-fg { color: hsl(50, 30%, 25%); }
.u-71 { padding:7px; margin:22px; border-radius:11px; }
.u-71-bg { background: hsl(137, 50%, 90%); }
.u-71-fg { color: hsl(61, 30%, 25%); }
.u-72 { padding:8px; margin:0px; border-radius:0px; }
.u-72-bg { background: hsl(144, 50%, 90%); }
.u-72-fg { color: hsl(72, 30%, 25%); }
.u-73 { padding:9px; margin:2px; border-radius:1px; }
.u-73-bg { background: hsl(151, 50%, 90%); }
.u-73-fg { color: hsl(83, 30%, 25%); }
.u-74 { padding:10px; margin:4px; border-radius:2px; }
.u-74-bg { background: hsl(158, 50%, 90%); }
.u-74-fg { color: hsl(94, 30%, 25%); }
.u-75 { padding:11px; margin:6px; border-radius:3px; }
.u-75-bg { background: hsl(165, 50%, 90%); }
.u-75-fg { color: hsl(105, 30%, 25%); }
.u-76 { padding:12px; margin:8px; border-radius:4px; }
.u-76-bg { background: hsl(172, 50%, 90%); }
.u-76-fg { color: hsl(116, 30%, 25%); }
.u-77 { padding:13px; margin:10px; border-radius:5px; }
.u-77-bg { background: hsl(179, 50%, 90%); }
.u-77-fg { color: hsl(127, 30%, 25%); }
.u-78 { padding:14px; margin:12px; border-radius:6px; }
.u-78-bg { background: hsl(186, 50%, 90%); }
.u-78-fg { color: hsl(138, 30%, 25%); }
.u-79 { padding:15px; margin:14px; border-radius:7px; }
.u-79-bg { background: hsl(193, 50%, 90%); }
.u-79-fg { color: hsl(149, 30%, 25%); }
.u-80 { padding:0px; margin:16px; border-radius:8px; }
.u-80-bg { background: hsl(200, 50%, 90%); }
.u-80-fg { color: hsl(160, 30%, 25%); }
.u-81 { padding:1px; margin:18px; border-radius:9px; }
.u-81-bg { background: hsl(207, 50%, 90%); }
.u-81-fg { color: hsl(171, 30%, 25%); }
.u-82 { padding:2px; margin:20px; border-radius:10px; }
.u-82-bg { background: hsl(214, 50%, 90%); }
.u-82-fg { color: hsl(182, 30%, 25%); }
.u-83 { padding:3px; margin:22px; border-radius:11px; }
.u-83-bg { background: hsl(221, 50%, 90%); }
.u-83-fg { color: hsl(193, 30%, 25%); }
.u-84 { padding:4px; margin:0px; border-radius:0px; }
.u-84-bg { background: hsl(228, 50%, 90%); }
.u-84-fg { color: hsl(204, 30%, 25%); }
.u-85 { padding:5px; margin:2px; border-radius:1px; }
.u-85-bg { background: hsl(235, 50%, 90%); }
.u-85-fg { color: hsl(215, 30%, 25%); }
.u-86 { padding:6px; margin:4px; border-radius:2px; }
.u-86-bg { background: hsl(242, 50%, 90%); }
.u-86-fg { color: hsl(226, 30%, 25%); }
.u-87 { padding:7px; margin:6px; border-radius:3px; }
.u-87-bg { background: hsl(249, 50%, 90%); }
.u-87-fg { color: hsl(237, 30%, 25%); }
.u-88 { padding:8px; margin:8px; border-radius:4px; }
.u-88-bg { background: hsl(256, 50%, 90%); }
.u-88-fg { color: hsl(248, 30%, 25%); }
.u-89 { padding:9px; margin:10px; border-radius:5px; }
.u-89-bg { background: hsl(263, 50%, 90%); }
.u-89-fg { color: hsl(259, 30%, 25%); }
.u-90 { padding:10px; margin:12px; border-radius:6px; }
.u-90-bg { background: hsl(270, 50%, 90%); }
.u-90-fg { color: hsl(270, 30%, 25%); }
.u-91 { padding:11px; margin:14px; border-radius:7px; }
.u-91-bg { background: hsl(277, 50%, 90%); }
.u-91-fg { color: hsl(281, 30%, 25%); }
.u-92 { padding:12px; margin:16px; border-radius:8px; }
.u-92-bg { background: hsl(284, 50%, 90%); }
.u-92-fg { color: hsl(292, 30%, 25%); }
.u-93 { padding:13px; margin:18px; border-radius:9px; }
.u-93-bg { background: hsl(291, 50%, 90%); }
.u-93-fg { color: hsl(303, 30%, 25%); }
.u-94 { padding:14px; margin:20px; border-radius:10px; }
.u-94-bg { background: hsl(298, 50%, 90%); }
.u-94-fg { color: hsl(314, 30%, 25%); }
.u-95 { padding:15px; margin:22px; border-radius:11px; }
.u-95-bg { background: hsl(305, 50%, 90%); }
.u-95-fg { color: hsl(325, 30%, 25%); }
.u-96 { padding:0px; margin:0px; border-radius:0px; }
.u-96-bg { background: hsl(312, 50%, 90%); }
.u-96-fg { color: hsl(336, 30%, 25%); }
.u-97 { padding:1px; margin:2px; border-radius:1px; }
.u-97-bg { background: hsl(319, 50%, 90%); }
.u-97-fg { color: hsl(347, 30%, 25%); }
.u-98 { padding:2px; margin:4px; border-radius:2px; }
.u-98-bg { background: hsl(326, 50%, 90%); }
.u-98-fg { color: hsl(358, 30%, 25%); }
.u-99 { padding:3px; margin:6px; border-radius:3px; }
.u-99-bg { background: hsl(333, 50%, 90%); }
.u-99-fg { color: hsl(9, 30%, 25%); }
.u-100 { padding:4px; margin:8px; border-radius:4px; }
.u-100-bg { background: hsl(340, 50%, 90%); }
.u-100-fg { color: hsl(20, 30%, 25%); }
.u-101 { padding:5px; margin:10px; border-radius:5px; }
.u-101-bg { background: hsl(347, 50%, 90%); }
.u-101-fg { color: hsl(31, 30%, 25%); }
.u-102 { padding:6px; margin:12px; border-radius:6px; }
.u-102-bg { background: hsl(354, 50%, 90%); }
.u-102-fg { color: hsl(42, 30%, 25%); }
.u-103 { padding:7px; margin:14px; border-radius:7px; }
.u-103-bg { background: hsl(1, 50%, 90%); }
.u-103-fg { color: hsl(53, 30%, 25%); }
.u-104 { padding:8px; margin:16px; border-radius:8px; }
.u-104-bg { background: hsl(8, 50%, 90%); }
.u-104-fg { color: hsl(64, 30%, 25%); }
.u-105 { padding:9px; margin:18px; border-radius:9px; }
.u-105-bg { background: hsl(15, 50%, 90%); }
.u-105-fg { color: hsl(75, 30%, 25%); }
.u-106 { padding:10px; margin:20px; border-radius:10px; }
.u-106-bg { background: hsl(22, 50%, 90%); }
.u-106-fg { color: hsl(86, 30%, 25%); }
.u-107 { padding:11px; margin:22px; border-radius:11px; }
.u-107-bg { background: hsl(29, 50%, 90%); }
.u-107-fg { color: hsl(97, 30%, 25%); }
.u-108 { padding:12px; margin:0px; border-radius:0px; }
.u-108-bg { background: hsl(36, 50%, 90%); }
.u-108-fg { color: hsl(108, 30%, 25%); }
.u-109 { padding:13px; margin:2px; border-radius:1px; }
.u-109-bg { background: hsl(43, 50%, 90%); }
.u-109-fg { color: hsl(119, 30%, 25%); }
.u-110 { padding:14px; margin:4px; border-radius:2px; }
.u-110-bg { background: hsl(50, 50%, 90%); }
.u-110-fg { color: hsl(130, 30%, 25%); }
.u-111 { padding:15px; margin:6px; border-radius:3px; }
.u-111-bg { background: hsl(57, 50%, 90%); }
.u-111-fg { color: hsl(141, 30%, 25%); }
.u-112 { padding:0px; margin:8px; border-radius:4px; }
.u-112-bg { background: hsl(64, 50%, 90%); }
.u-112-fg { color: hsl(152, 30%, 25%); }
.u-113 { padding:1px; margin:10px; border-radius:5px; }
.u-113-bg { background: hsl(71, 50%, 90%); }
.u-113-fg { color: hsl(163, 30%, 25%); }
.u-114 { padding:2px; margin:12px; border-radius:6px; }
.u-114-bg { background: hsl(78, 50%, 90%); }
.u-114-fg { color: hsl(174, 30%, 25%); }
.u-115 { padding:3px; margin:14px; border-radius:7px; }
.u-115-bg { background: hsl(85, 50%, 90%); }
.u-115-fg { color: hsl(185, 30%, 25%); }
.u-116 { padding:4px; margin:16px; border-radius:8px; }
.u-116-bg { background: hsl(92, 50%, 90%); }
.u-116-fg { color: hsl(196, 30%, 25%); }
.u-117 { padding:5px; margin:18px; border-radius:9px; }
.u-117-bg { background: hsl(99, 50%, 90%); }
.u-117-fg { color: hsl(207, 30%, 25%); }
.u-118 { padding:6px; margin:20px; border-radius:10px; }
.u-118-bg { background: hsl(106, 50%, 90%); }
.u-118-fg { color: hsl(218, 30%, 25%); }
.u-119 { padding:7px; margin:22px; border-radius:11px; }
.u-119-bg { background: hsl(113, 50%, 90%); }
.u-119-fg { color: hsl(229, 30%, 25%); }
.u-120 { padding:8px; margin:0px; border-radius:0px; }
.u-120-bg { background: hsl(120, 50%, 90%); }
.u-120-fg { color: hsl(240, 30%, 25%); }
.u-121 { padding:9px; margin:2px; border-radius:1px; }
.u-121-bg { background: hsl(127, 50%, 90%); }
.u-121-fg { color: hsl(251, 30%, 25%); }
.u-122 { padding:10px; margin:4px; border-radius:2px; }
.u-122-bg { background: hsl(134, 50%, 90%); }
.u-122-fg { color: hsl(262, 30%, 25%); }
.u-123 { padding:11px; margin:6px; border-radius:3px; }
.u-123-bg { background: hsl(141, 50%, 90%); }
.u-123-fg { color: hsl(273, 30%, 25%); }
.u-124 { padding:12px; margin:8px; border-radius:4px; }
.u-124-bg { background: hsl(148, 50%, 90%); }
.u-124-fg { color: hsl(284, 30%, 25%); }
.u-125 { padding:13px; margin:10px; border-radius:5px; }
.u-125-bg { background: hsl(155, 50%, 90%); }
.u-125-fg { color: hsl(295, 30%, 25%); }
.u-126 { padding:14px; margin:12px; border-radius:6px; }
.u-126-bg { background: hsl(162, 50%, 90%); }
.u-126-fg { color: hsl(306, 30%, 25%); }
.u-127 { padding:15px; margin:14px; border-radius:7px; }
.u-127-bg { background: hsl(169, 50%, 90%); }
.u-127-fg { color: hsl(317, 30%, 25%); }
.u-128 { padding:0px; margin:16px; border-radius:8px; }
.u-128-bg { background: hsl(176, 50%, 90%); }
.u-128-fg { color: hsl(328, 30%, 25%); }
.u-129 { padding:1px; margin:18px; border-radius:9px; }
.u-129-bg { background: hsl(183, 50%, 90%); }
.u-129-fg { color: hsl(339, 30%, 25%); }
.u-130 { padding:2px; margin:20px; border-radius:10px; }
.u-130-bg { background: hsl(190, 50%, 90%); }
.u-130-fg { color: hsl(350, 30%, 25%); }
.u-131 { padding:3px; margin:22px; border-radius:11px; }
.u-131-bg { background: hsl(197, 50%, 90%); }
.u-131-fg { color: hsl(1, 30%, 25%); }
.u-132 { padding:4px; margin:0px; border-radius:0px; }
.u-132-bg { background: hsl(204, 50%, 90%); }
.u-132-fg { color: hsl(12, 30%, 25%); }
.u-133 { padding:5px; margin:2px; border-radius:1px; }
.u-133-bg { background: hsl(211, 50%, 90%); }
.u-133-fg { color: hsl(23, 30%, 25%); }
.u-134 { padding:6px; margin:4px; border-radius:2px; }
.u-134-bg { background: hsl(218, 50%, 90%); }
.u-134-fg { color: hsl(34, 30%, 25%); }
.u-135 { padding:7px; margin:6px; border-radius:3px; }
.u-135-bg { background: hsl(225, 50%, 90%); }
.u-135-fg { color: hsl(45, 30%, 25%); }
.u-136 { padding:8px; margin:8px; border-radius:4px; }
.u-136-bg { background: hsl(232, 50%, 90%); }
.u-136-fg { color: hsl(56, 30%, 25%); }
.u-137 { padding:9px; margin:10px; border-radius:5px; }
.u-137-bg { background: hsl(239, 50%, 90%); }
.u-137-fg { color: hsl(67, 30%, 25%); }
.u-138 { padding:10px; margin:12px; border-radius:6px; }
.u-138-bg { background: hsl(246, 50%, 90%); }
.u-138-fg { color: hsl(78, 30%, 25%); }
.u-139 { padding:11px; margin:14px; border-radius:7px; }
.u-139-bg { background: hsl(253, 50%, 90%); }
.u-139-fg { color: hsl(89, 30%, 25%); }
.u-140 { padding:12px; margin:16px; border-radius:8px; }
.u-140-bg { background: hsl(260, 50%, 90%); }
.u-140-fg { color: hsl(100, 30%, 25%); }
.u-141 { padding:13px; margin:18px; border-radius:9px; }
.u-141-bg { background: hsl(267, 50%, 90%); }
.u-141-fg { color: hsl(111, 30%, 25%); }
.u-142 { padding:14px; margin:20px; border-radius:10px; }
.u-142-bg { background: hsl(274, 50%, 90%); }
.u-142-fg { color: hsl(122, 30%, 25%); }
.u-143 { padding:15px; margin:22px; border-radius:11px; }
.u-143-bg { background: hsl(281, 50%, 90%); }
.u-143-fg { color: hsl(133, 30%, 25%); }
.u-144 { padding:0px; margin:0px; border-radius:0px; }
.u-144-bg { background: hsl(288, 50%, 90%); }
.u-144-fg { color: hsl(144, 30%, 25%); }
.u-145 { padding:1px; margin:2px; border-radius:1px; }
.u-145-bg { background: hsl(295, 50%, 90%); }
.u-145-fg { color: hsl(155, 30%, 25%); }
.u-146 { padding:2px; margin:4px; border-radius:2px; }
.u-146-bg { background: hsl(302, 50%, 90%); }
.u-146-fg { color: hsl(166, 30%, 25%); }
.u-147 { padding:3px; margin:6px; border-radius:3px; }
.u-147-bg { background: hsl(309, 50%, 90%); }
.u-147-fg { color: hsl(177, 30%, 25%); }
.u-148 { padding:4px; margin:8px; border-radius:4px; }
.u-148-bg { background: hsl(316, 50%, 90%); }
.u-148-fg { color: hsl(188, 30%, 25%); }
.u-149 { padding:5px; margin:10px; border-radius:5px; }
.u-149-bg { background: hsl(323, 50%, 90%); }
.u-149-fg { color: hsl(199, 30%, 25%); }
.u-150 { padding:6px; margin:12px; border-radius:6px; }
.u-150-bg { background: hsl(330, 50%, 90%); }
.u-150-fg { color: hsl(210, 30%, 25%); }
.u-151 { padding:7px; margin:14px; border-radius:7px; }
.u-151-bg { background: hsl(337, 50%, 90%); }
.u-151-fg { color: hsl(221, 30%, 25%); }
.u-152 { padding:8px; margin:16px; border-radius:8px; }
.u-152-bg { background: hsl(344, 50%, 90%); }
.u-152-fg { color: hsl(232, 30%, 25%); }
.u-153 { padding:9px; margin:18px; border-radius:9px; }
.u-153-bg { background: hsl(351, 50%, 90%); }
.u-153-fg { color: hsl(243, 30%, 25%); }
.u-154 { padding:10px; margin:20px; border-radius:10px; }
.u-154-bg { background: hsl(358, 50%, 90%); }
.u-154-fg { color: hsl(254, 30%, 25%); }
.u-155 { padding:11px; margin:22px; border-radius:11px; }
.u-155-bg { background: hsl(5, 50%, 90%); }
.u-155-fg { color: hsl(265, 30%, 25%); }
.u-156 { padding:12px; margin:0px; border-radius:0px; }
.u-156-bg { background: hsl(12, 50%, 90%); }
.u-156-fg { color: hsl(276, 30%, 25%); }
.u-157 { padding:13px; margin:2px; border-radius:1px; }
.u-157-bg { background: hsl(19, 50%, 90%); }
.u-157-fg { color: hsl(287, 30%, 25%); }
.u-158 { padding:14px; margin:4px; border-radius:2px; }
.u-158-bg { background: hsl(26, 50%, 90%); }
.u-158-fg { color: hsl(298, 30%, 25%); }
.u-159 { padding:15px; margin:6px; border-radius:3px; }
.u-159-bg { background: hsl(33, 50%, 90%); }
.u-159-fg { color: hsl(309, 30%, 25%); }
.u-160 { padding:0px; margin:8px; border-radius:4px; }
.u-160-bg { background: hsl(40, 50%, 90%); }
.u-160-fg { color: hsl(320, 30%, 25%); }
.u-161 { padding:1px; margin:10px; border-radius:5px; }
.u-161-bg { background: hsl(47, 50%, 90%); }
.u-161-fg { color: hsl(331, 30%, 25%); }
.u-162 { padding:2px; margin:12px; border-radius:6px; }
.u-162-bg { background: hsl(54, 50%, 90%); }
.u-162-fg { color: hsl(342, 30%, 25%); }
.u-163 { padding:3px; margin:14px; border-radius:7px; }
.u-163-bg { background: hsl(61, 50%, 90%); }
.u-163-fg { color: hsl(353, 30%, 25%); }
.u-164 { padding:4px; margin:16px; border-radius:8px; }
.u-164-bg { background: hsl(68, 50%, 90%); }
.u-164-fg { color: hsl(4, 30%, 25%); }
.u-165 { padding:5px; margin:18px; border-radius:9px; }
.u-165-bg { background: hsl(75, 50%, 90%); }
.u-165-fg { color: hsl(15, 30%, 25%); }
.u-166 { padding:6px; margin:20px; border-radius:10px; }
.u-166-bg { background: hsl(82, 50%, 90%); }
.u-166-fg { color: hsl(26, 30%, 25%); }
.u-167 { padding:7px; margin:22px; border-radius:11px; }
.u-167-bg { background: hsl(89, 50%, 90%); }
.u-167-fg { color: hsl(37, 30%, 25%); }
.u-168 { padding:8px; margin:0px; border-radius:0px; }
.u-168-bg { background: hsl(96, 50%, 90%); }
.u-168-fg { color: hsl(48, 30%, 25%); }
.u-169 { padding:9px; margin:2px; border-radius:1px; }
.u-169-bg { background: hsl(103, 50%, 90%); }
.u-169-fg { color: hsl(59, 30%, 25%); }
.u-170 { padding:10px; margin:4px; border-radius:2px; }
.u-170-bg { background: hsl(110, 50%, 90%); }
.u-170-fg { color: hsl(70, 30%, 25%); }
.u-171 { padding:11px; margin:6px; border-radius:3px; }
.u-171-bg { background: hsl(117, 50%, 90%); }
.u-171-fg { color: hsl(81, 30%, 25%); }
.u-172 { padding:12px; margin:8px; border-radius:4px; }
.u-172-bg { background: hsl(124, 50%, 90%); }
.u-172-fg { color: hsl(92, 30%, 25%); }
.u-173 { padding:13px; margin:10px; border-radius:5px; }
.u-173-bg { background: hsl(131, 50%, 90%); }
.u-173-fg { color: hsl(103, 30%, 25%); }
.u-174 { padding:14px; margin:12px; border-radius:6px; }
.u-174-bg { background: hsl(138, 50%, 90%); }
.u-174-fg { color: hsl(114, 30%, 25%); }
.u-175 { padding:15px; margin:14px; border-radius:7px; }
.u-175-bg { background: hsl(145, 50%, 90%); }
.u-175-fg { color: hsl(125, 30%, 25%); }
.u-176 { padding:0px; margin:16px; border-radius:8px; }
.u-176-bg { background: hsl(152, 50%, 90%); }
.u-176-fg { color: hsl(136, 30%, 25%); }
.u-177 { padding:1px; margin:18px; border-radius:9px; }
.u-177-bg { background: hsl(159, 50%, 90%); }
.u-177-fg { color: hsl(147, 30%, 25%); }
.u-178 { padding:2px; margin:20px; border-radius:10px; }
.u-178-bg { background: hsl(166, 50%, 90%); }
.u-178-fg { color: hsl(158, 30%, 25%); }
.u-179 { padding:3px; margin:22px; border-radius:11px; }
.u-179-bg { background: hsl(173, 50%, 90%); }
.u-179-fg { color: hsl(169, 30%, 25%); }
.u-180 { padding:4px; margin:0px; border-radius:0px; }
.u-180-bg { background: hsl(180, 50%, 90%); }
.u-180-fg { color: hsl(180, 30%, 25%); }
.u-181 { padding:5px; margin:2px; border-radius:1px; }
.u-181-bg { background: hsl(187, 50%, 90%); }
.u-181-fg { color: hsl(191, 30%, 25%); }
.u-182 { padding:6px; margin:4px; border-radius:2px; }
.u-182-bg { background: hsl(194, 50%, 90%); }
.u-182-fg { color: hsl(202, 30%, 25%); }
.u-183 { padding:7px; margin:6px; border-radius:3px; }
.u-183-bg { background: hsl(201, 50%, 90%); }
.u-183-fg { color: hsl(213, 30%, 25%); }
.u-184 { padding:8px; margin:8px; border-radius:4px; }
.u-184-bg { background: hsl(208, 50%, 90%); }
.u-184-fg { color: hsl(224, 30%, 25%); }
.u-185 { padding:9px; margin:10px; border-radius:5px; }
.u-185-bg { background: hsl(215, 50%, 90%); }
.u-185-fg { color: hsl(235, 30%, 25%); }
.u-186 { padding:10px; margin:12px; border-radius:6px; }
.u-186-bg { background: hsl(222, 50%, 90%); }
.u-186-fg { color: hsl(246, 30%, 25%); }
.u-187 { padding:11px; margin:14px; border-radius:7px; }
.u-187-bg { background: hsl(229, 50%, 90%); }
.u-187-fg { color: hsl(257, 30%, 25%); }
.u-188 { padding:12px; margin:16px; border-radius:8px; }
.u-188-bg { background: hsl(236, 50%, 90%); }
.u-188-fg { color: hsl(268, 30%, 25%); }
.u-189 { padding:13px; margin:18px; border-radius:9px; }
.u-189-bg { background: hsl(243, 50%, 90%); }
.u-189-fg { color: hsl(279, 30%, 25%); }
.u-190 { padding:14px; margin:20px; border-radius:10px; }
.u-190-bg { background: hsl(250, 50%, 90%); }
.u-190-fg { color: hsl(290, 30%, 25%); }
.u-191 { padding:15px; margin:22px; border-radius:11px; }
.u-191-bg { background: hsl(257, 50%, 90%); }
.u-191-fg { color: hsl(301, 30%, 25%); }
.u-192 { padding:0px; margin:0px; border-radius:0px; }
.u-192-bg { background: hsl(264, 50%, 90%); }
.u-192-fg { color: hsl(312, 30%, 25%); }
.u-193 { padding:1px; margin:2px; border-radius:1px; }
.u-193-bg { background: hsl(271, 50%, 90%); }
.u-193-fg { color: hsl(323, 30%, 25%); }
.u-194 { padding:2px; margin:4px; border-radius:2px; }
.u-194-bg { background: hsl(278, 50%, 90%); }
.u-194-fg { color: hsl(334, 30%, 25%); }
.u-195 { padding:3px; margin:6px; border-radius:3px; }
.u-195-bg { background: hsl(285, 50%, 90%); }
.u-195-fg { color: hsl(345, 30%, 25%); }
.u-196 { padding:4px; margin:8px; border-radius:4px; }
.u-196-bg { background: hsl(292, 50%, 90%); }
.u-196-fg { color: hsl(356, 30%, 25%); }
.u-197 { padding:5px; margin:10px; border-radius:5px; }
.u-197-bg { background: hsl(299, 50%, 90%); }
.u-197-fg { color: hsl(7, 30%, 25%); }
.u-198 { padding:6px; margin:12px; border-radius:6px; }
.u-198-bg { background: hsl(306, 50%, 90%); }
.u-198-fg { color: hsl(18, 30%, 25%); }
.u-199 { padding:7px; margin:14px; border-radius:7px; }
.u-199-bg { background: hsl(313, 50%, 90%); }
.u-199-fg { color: hsl(29, 30%, 25%); }
.u-200 { padding:8px; margin:16px; border-radius:8px; }
.u-200-bg { background: hsl(320, 50%, 90%); }
.u-200-fg { color: hsl(40, 30%, 25%); }
.u-201 { padding:9px; margin:18px; border-radius:9px; }
.u-201-bg { background: hsl(327, 50%, 90%); }
.u-201-fg { color: hsl(51, 30%, 25%); }
.u-202 { padding:10px; margin:20px; border-radius:10px; }
.u-202-bg { background: hsl(334, 50%, 90%); }
.u-202-fg { color: hsl(62, 30%, 25%); }
.u-203 { padding:11px; margin:22px; border-radius:11px; }
.u-203-bg { background: hsl(341, 50%, 90%); }
.u-203-fg { color: hsl(73, 30%, 25%); }
.u-204 { padding:12px; margin:0px; border-radius:0px; }
.u-204-bg { background: hsl(348, 50%, 90%); }
.u-204-fg { color: hsl(84, 30%, 25%); }
.u-205 { padding:13px; margin:2px; border-radius:1px; }
.u-205-bg { background: hsl(355, 50%, 90%); }
.u-205-fg { color: hsl(95, 30%, 25%); }
.u-206 { padding:14px; margin:4px; border-radius:2px; }
.u-206-bg { background: hsl(2, 50%, 90%); }
.u-206-fg { color: hsl(106, 30%, 25%); }
.u-207 { padding:15px; margin:6px; border-radius:3px; }
.u-207-bg { background: hsl(9, 50%, 90%); }
.u-207-fg { color: hsl(117, 30%, 25%); }
.u-208 { padding:0px; margin:8px; border-radius:4px; }
.u-208-bg { background: hsl(16, 50%, 90%); }
.u-208-fg { color: hsl(128, 30%, 25%); }
.u-209 { padding:1px; margin:10px; border-radius:5px; }
.u-209-bg { background: hsl(23, 50%, 90%); }
.u-209-fg { color: hsl(139, 30%, 25%); }
.u-210 { padding:2px; margin:12px; border-radius:6px; }
.u-210-bg { background: hsl(30, 50%, 90%); }
.u-210-fg { color: hsl(150, 30%, 25%); }
.u-211 { padding:3px; margin:14px; border-radius:7px; }
.u-211-bg { background: hsl(37, 50%, 90%); }
.u-211-fg { color: hsl(161, 30%, 25%); }
.u-212 { padding:4px; margin:16px; border-radius:8px; }
.u-212-bg { background: hsl(44, 50%, 90%); }
.u-212-fg { color: hsl(172, 30%, 25%); }
.u-213 { padding:5px; margin:18px; border-radius:9px; }
.u-213-bg { background: hsl(51, 50%, 90%); }
.u-213-fg { color: hsl(183, 30%, 25%); }
.u-214 { padding:6px; margin:20px; border-radius:10px; }
.u-214-bg { background: hsl(58, 50%, 90%); }
.u-214-fg { color: hsl(194, 30%, 25%); }
.u-215 { padding:7px; margin:22px; border-radius:11px; }
.u-215-bg { background: hsl(65, 50%, 90%); }
.u-215-fg { color: hsl(205, 30%, 25%); }
.u-216 { padding:8px; margin:0px; border-radius:0px; }
.u-216-bg { background: hsl(72, 50%, 90%); }
.u-216-fg { color: hsl(216, 30%, 25%); }
.u-217 { padding:9px; margin:2px; border-radius:1px; }
.u-217-bg { background: hsl(79, 50%, 90%); }
.u-217-fg { color: hsl(227, 30%, 25%); }
.u-218 { padding:10px; margin:4px; border-radius:2px; }
.u-218-bg { background: hsl(86, 50%, 90%); }
.u-218-fg { color: hsl(238, 30%, 25%); }
.u-219 { padding:11px; margin:6px; border-radius:3px; }
.u-219-bg { background: hsl(93, 50%, 90%); }
.u-219-fg { color: hsl(249, 30%, 25%); }
.u-220 { padding:12px; margin:8px; border-radius:4px; }
.u-220-bg { background: hsl(100, 50%, 90%); }
.u-220-fg { color: hsl(260, 30%, 25%); }
.u-221 { padding:13px; margin:10px; border-radius:5px; }
.u-221-bg { background: hsl(107, 50%, 90%); }
.u-221-fg { color: hsl(271, 30%, 25%); }
.u-222 { padding:14px; margin:12px; border-radius:6px; }
.u-222-bg { background: hsl(114, 50%, 90%); }
.u-222-fg { color: hsl(282, 30%, 25%); }
.u-223 { padding:15px; margin:14px; border-radius:7px; }
.u-223-bg { background: hsl(121, 50%, 90%); }
.u-223-fg { color: hsl(293, 30%, 25%); }
.u-224 { padding:0px; margin:16px; border-radius:8px; }
.u-224-bg { background: hsl(128, 50%, 90%); }
.u-224-fg { color: hsl(304, 30%, 25%); }
.u-225 { padding:1px; margin:18px; border-radius:9px; }
.u-225-bg { background: hsl(135, 50%, 90%); }
.u-225-fg { color: hsl(315, 30%, 25%); }
.u-226 { padding:2px; margin:20px; border-radius:10px; }
.u-226-bg { background: hsl(142, 50%, 90%); }
.u-226-fg { color: hsl(326, 30%, 25%); }
.u-227 { padding:3px; margin:22px; border-radius:11px; }
.u-227-bg { background: hsl(149, 50%, 90%); }
.u-227-fg { color: hsl(337, 30%, 25%); }
.u-228 { padding:4px; margin:0px; border-radius:0px; }
.u-228-bg { background: hsl(156, 50%, 90%); }
.u-228-fg { color: hsl(348, 30%, 25%); }
.u-229 { padding:5px; margin:2px; border-radius:1px; }
.u-229-bg { background: hsl(163, 50%, 90%); }
.u-229-fg { color: hsl(359, 30%, 25%); }
.u-230 { padding:6px; margin:4px; border-radius:2px; }
.u-230-bg { background: hsl(170, 50%, 90%); }
.u-230-fg { color: hsl(10, 30%, 25%); }
.u-231 { padding:7px; margin:6px; border-radius:3px; }
.u-231-bg { background: hsl(177, 50%, 90%); }
.u-231-fg { color: hsl(21, 30%, 25%); }
.u-232 { padding:8px; margin:8px; border-radius:4px; }
.u-232-bg { background: hsl(184, 50%, 90%); }
.u-232-fg { color: hsl(32, 30%, 25%); }
.u-233 { padding:9px; margin:10px; border-radius:5px; }
.u-233-bg { background: hsl(191, 50%, 90%); }
.u-233-fg { color: hsl(43, 30%, 25%); }
.u-234 { padding:10px; margin:12px; border-radius:6px; }
.u-234-bg { background: hsl(198, 50%, 90%); }
.u-234-fg { color: hsl(54, 30%, 25%); }
.u-235 { padding:11px; margin:14px; border-radius:7px; }
.u-235-bg { background: hsl(205, 50%, 90%); }
.u-235-fg { color: hsl(65, 30%, 25%); }
.u-236 { padding:12px; margin:16px; border-radius:8px; }
.u-236-bg { background: hsl(212, 50%, 90%); }
.u-236-fg { color: hsl(76, 30%, 25%); }
.u-237 { padding:13px; margin:18px; border-radius:9px; }
.u-237-bg { background: hsl(219, 50%, 90%); }
.u-237-fg { color: hsl(87, 30%, 25%); }
.u-238 { padding:14px; margin:20px; border-radius:10px; }
.u-238-bg { background: hsl(226, 50%, 90%); }
.u-238-fg { color: hsl(98, 30%, 25%); }
.u-239 { padding:15px; margin:22px; border-radius:11px; }
.u-239-bg { background: hsl(233, 50%, 90%); }
.u-239-fg { color: hsl(109, 30%, 25%); }
.u-240 { padding:0px; margin:0px; border-radius:0px; }
.u-240-bg { background: hsl(240, 50%, 90%); }
.u-240-fg { color: hsl(120, 30%, 25%); }
.u-241 { padding:1px; margin:2px; border-radius:1px; }
.u-241-bg { background: hsl(247, 50%, 90%); }
.u-241-fg { color: hsl(131, 30%, 25%); }
.u-242 { padding:2px; margin:4px; border-radius:2px; }
.u-242-bg { background: hsl(254, 50%, 90%); }
.u-242-fg { color: hsl(142, 30%, 25%); }
.u-243 { padding:3px; margin:6px; border-radius:3px; }
.u-243-bg { background: hsl(261, 50%, 90%); }
.u-243-fg { color: hsl(153, 30%, 25%); }
.u-244 { padding:4px; margin:8px; border-radius:4px; }
.u-244-bg { background: hsl(268, 50%, 90%); }
.u-244-fg { color: hsl(164, 30%, 25%); }
.u-245 { padding:5px; margin:10px; border-radius:5px; }
.u-245-bg { background: hsl(275, 50%, 90%); }
.u-245-fg { color: hsl(175, 30%, 25%); }
.u-246 { padding:6px; margin:12px; border-radius:6px; }
.u-246-bg { background: hsl(282, 50%, 90%); }
.u-246-fg { color: hsl(186, 30%, 25%); }
.u-247 { padding:7px; margin:14px; border-radius:7px; }
.u-247-bg { background: hsl(289, 50%, 90%); }
.u-247-fg { color: hsl(197, 30%, 25%); }
.u-248 { padding:8px; margin:16px; border-radius:8px; }
.u-248-bg { background: hsl(296, 50%, 90%); }
.u-248-fg { color: hsl(208, 30%, 25%); }
.u-249 { padding:9px; margin:18px; border-radius:9px; }
.u-249-bg { background: hsl(303, 50%, 90%); }
.u-249-fg { color: hsl(219, 30%, 25%); }
.u-250 { padding:10px; margin:20px; border-radius:10px; }
.u-250-bg { background: hsl(310, 50%, 90%); }
.u-250-fg { color: hsl(230, 30%, 25%); }
.u-251 { padding:11px; margin:22px; border-radius:11px; }
.u-251-bg { background: hsl(317, 50%, 90%); }
.u-251-fg { color: hsl(241, 30%, 25%); }
.u-252 { padding:12px; margin:0px; border-radius:0px; }
.u-252-bg { background: hsl(324, 50%, 90%); }
.u-252-fg { color: hsl(252, 30%, 25%); }
.u-253 { padding:13px; margin:2px; border-radius:1px; }
.u-253-bg { background: hsl(331, 50%, 90%); }
.u-253-fg { color: hsl(263, 30%, 25%); }
.u-254 { padding:14px; margin:4px; border-radius:2px; }
.u-254-bg { background: hsl(338, 50%, 90%); }
.u-254-fg { color: hsl(274, 30%, 25%); }
.u-255 { padding:15px; margin:6px; border-radius:3px; }
.u-255-bg { background: hsl(345, 50%, 90%); }
.u-255-fg { color: hsl(285, 30%, 25%); }
.u-256 { padding:0px; margin:8px; border-radius:4px; }
.u-256-bg { background: hsl(352, 50%, 90%); }
.u-256-fg { color: hsl(296, 30%, 25%); }
.u-257 { padding:1px; margin:10px; border-radius:5px; }
.u-257-bg { background: hsl(359, 50%, 90%); }
.u-257-fg { color: hsl(307, 30%, 25%); }
.u-258 { padding:2px; margin:12px; border-radius:6px; }
.u-258-bg { background: hsl(6, 50%, 90%); }
.u-258-fg { color: hsl(318, 30%, 25%); }
.u-259 { padding:3px; margin:14px; border-radius:7px; }
.u-259-bg { background: hsl(13, 50%, 90%); }
.u-259-fg { color: hsl(329, 30%, 25%); }
.u-260 { padding:4px; margin:16px; border-radius:8px; }
.u-260-bg { background: hsl(20, 50%, 90%); }
.u-260-fg { color: hsl(340, 30%, 25%); }
.u-261 { padding:5px; margin:18px; border-radius:9px; }
.u-261-bg { background: hsl(27, 50%, 90%); }
.u-261-fg { color: hsl(351, 30%, 25%); }
.u-262 { padding:6px; margin:20px; border-radius:10px; }
.u-262-bg { background: hsl(34, 50%, 90%); }
.u-262-fg { color: hsl(2, 30%, 25%); }
.u-263 { padding:7px; margin:22px; border-radius:11px; }
.u-263-bg { background: hsl(41, 50%, 90%); }
.u-263-fg { color: hsl(13, 30%, 25%); }
.u-264 { padding:8px; margin:0px; border-radius:0px; }
.u-264-bg { background: hsl(48, 50%, 90%); }
.u-264-fg { color: hsl(24, 30%, 25%); }
.u-265 { padding:9px; margin:2px; border-radius:1px; }
.u-265-bg { background: hsl(55, 50%, 90%); }
.u-265-fg { color: hsl(35, 30%, 25%); }
.u-266 { padding:10px; margin:4px; border-radius:2px; }
.u-266-bg { background: hsl(62, 50%, 90%); }
.u-266-fg { color: hsl(46, 30%, 25%); }
.u-267 { padding:11px; margin:6px; border-radius:3px; }
.u-267-bg { background: hsl(69, 50%, 90%); }
.u-267-fg { color: hsl(57, 30%, 25%); }
.u-268 { padding:12px; margin:8px; border-radius:4px; }
.u-268-bg { background: hsl(76, 50%, 90%); }
.u-268-fg { color: hsl(68, 30%, 25%); }
.u-269 { padding:13px; margin:10px; border-radius:5px; }
.u-269-bg { background: hsl(83, 50%, 90%); }
.u-269-fg { color: hsl(79, 30%, 25%); }
.u-270 { padding:14px; margin:12px; border-radius:6px; }
.u-270-bg { background: hsl(90, 50%, 90%); }
.u-270-fg { color: hsl(90, 30%, 25%); }
.u-271 { padding:15px; margin:14px; border-radius:7px; }
.u-271-bg { background: hsl(97, 50%, 90%); }
.u-271-fg { color: hsl(101, 30%, 25%); }
.u-272 { padding:0px; margin:16px; border-radius:8px; }
.u-272-bg { background: hsl(104, 50%, 90%); }
.u-272-fg { color: hsl(112, 30%, 25%); }
.u-273 { padding:1px; margin:18px; border-radius:9px; }
.u-273-bg { background: hsl(111, 50%, 90%); }
.u-273-fg { color: hsl(123, 30%, 25%); }
.u-274 { padding:2px; margin:20px; border-radius:10px; }
.u-274-bg { background: hsl(118, 50%, 90%); }
.u-274-fg { color: hsl(134, 30%, 25%); }
.u-275 { padding:3px; margin:22px; border-radius:11px; }
.u-275-bg { background: hsl(125, 50%, 90%); }
.u-275-fg { color: hsl(145, 30%, 25%); }
.u-276 { padding:4px; margin:0px; border-radius:0px; }
.u-276-bg { background: hsl(132, 50%, 90%); }
.u-276-fg { color: hsl(156, 30%, 25%); }
.u-277 { padding:5px; margin:2px; border-radius:1px; }
.u-277-bg { background: hsl(139, 50%, 90%); }
.u-277-fg { color: hsl(167, 30%, 25%); }
.u-278 { padding:6px; margin:4px; border-radius:2px; }
.u-278-bg { background: hsl(146, 50%, 90%); }
.u-278-fg { color: hsl(178, 30%, 25%); }
.u-279 { padding:7px; margin:6px; border-radius:3px; }
.u-279-bg { background: hsl(153, 50%, 90%); }
.u-279-fg { color: hsl(189, 30%, 25%); }
.u-280 { padding:8px; margin:8px; border-radius:4px; }
.u-280-bg { background: hsl(160, 50%, 90%); }
.u-280-fg { color: hsl(200, 30%, 25%); }
.u-281 { padding:9px; margin:10px; border-radius:5px; }
.u-281-bg { background: hsl(167, 50%, 90%); }
.u-281-fg { color: hsl(211, 30%, 25%); }
.u-282 { padding:10px; margin:12px; border-radius:6px; }
.u-282-bg { background: hsl(174, 50%, 90%); }
.u-282-fg { color: hsl(222, 30%, 25%); }
.u-283 { padding:11px; margin:14px; border-radius:7px; }
.u-283-bg { background: hsl(181, 50%, 90%); }
.u-283-fg { color: hsl(233, 30%, 25%); }
.u-284 { padding:12px; margin:16px; border-radius:8px; }
.u-284-bg { background: hsl(188, 50%, 90%); }
.u-284-fg { color: hsl(244, 30%, 25%); }
.u-285 { padding:13px; margin:18px; border-radius:9px; }
.u-285-bg { background: hsl(195, 50%, 90%); }
.u-285-fg { color: hsl(255, 30%, 25%); }
.u-286 { padding:14px; margin:20px; border-radius:10px; }
.u-286-bg { background: hsl(202, 50%, 90%); }
.u-286-fg { color: hsl(266, 30%, 25%); }
.u-287 { padding:15px; margin:22px; border-radius:11px; }
.u-287-bg { background: hsl(209, 50%, 90%); }
.u-287-fg { color: hsl(277, 30%, 25%); }
.u-288 { padding:0px; margin:0px; border-radius:0px; }
.u-288-bg { background: hsl(216, 50%, 90%); }
.u-288-fg { color: hsl(288, 30%, 25%); }
.u-289 { padding:1px; margin:2px; border-radius:1px; }
.u-289-bg { background: hsl(223, 50%, 90%); }
.u-289-fg { color: hsl(299, 30%, 25%); }
.u-290 { padding:2px; margin:4px; border-radius:2px; }
.u-290-bg { background: hsl(230, 50%, 90%); }
.u-290-fg { color: hsl(310, 30%, 25%); }
.u-291 { padding:3px; margin:6px; border-radius:3px; }
.u-291-bg { background: hsl(237, 50%, 90%); }
.u-291-fg { color: hsl(321, 30%, 25%); }
.u-292 { padding:4px; margin:8px; border-radius:4px; }
.u-292-bg { background: hsl(244, 50%, 90%); }
.u-292-fg { color: hsl(332, 30%, 25%); }
.u-293 { padding:5px; margin:10px; border-radius:5px; }
.u-293-bg { background: hsl(251, 50%, 90%); }
.u-293-fg { color: hsl(343, 30%, 25%); }
.u-294 { padding:6px; margin:12px; border-radius:6px; }
.u-294-bg { background: hsl(258, 50%, 90%); }
.u-294-fg { color: hsl(354, 30%, 25%); }
.u-295 { padding:7px; margin:14px; border-radius:7px; }
.u-295-bg { background: hsl(265, 50%, 90%); }
.u-295-fg { color: hsl(5, 30%, 25%); }
.u-296 { padding:8px; margin:16px; border-radius:8px; }
.u-296-bg { background: hsl(272, 50%, 90%); }
.u-296-fg { color: hsl(16, 30%, 25%); }
.u-297 { padding:9px; margin:18px; border-radius:9px; }
.u-297-bg { background: hsl(279, 50%, 90%); }
.u-297-fg { color: hsl(27, 30%, 25%); }
.u-298 { padding:10px; margin:20px; border-radius:10px; }
.u-298-bg { background: hsl(286, 50%, 90%); }
.u-298-fg { color: hsl(38, 30%, 25%); }
.u-299 { padding:11px; margin:22px; border-radius:11px; }
.u-299-bg { background: hsl(293, 50%, 90%); }
.u-299-fg { color: hsl(49, 30%, 25%); }
.u-300 { padding:12px; margin:0px; border-radius:0px; }
.u-300-bg { background: hsl(300, 50%, 90%); }
.u-300-fg { color: hsl(60, 30%, 25%); }
.u-301 { padding:13px; margin:2px; border-radius:1px; }
.u-301-bg { background: hsl(307, 50%, 90%); }
.u-301-fg { color: hsl(71, 30%, 25%); }
.u-302 { padding:14px; margin:4px; border-radius:2px; }
.u-302-bg { background: hsl(314, 50%, 90%); }
.u-302-fg { color: hsl(82, 30%, 25%); }
.u-303 { padding:15px; margin:6px; border-radius:3px; }
.u-303-bg { background: hsl(321, 50%, 90%); }
.u-303-fg { color: hsl(93, 30%, 25%); }
.u-304 { padding:0px; margin:8px; border-radius:4px; }
.u-304-bg { background: hsl(328, 50%, 90%); }
.u-304-fg { color: hsl(104, 30%, 25%); }
.u-305 { padding:1px; margin:10px; border-radius:5px; }
.u-305-bg { background: hsl(335, 50%, 90%); }
.u-305-fg { color: hsl(115, 30%, 25%); }
.u-306 { padding:2px; margin:12px; border-radius:6px; }
.u-306-bg { background: hsl(342, 50%, 90%); }
.u-306-fg { color: hsl(126, 30%, 25%); }
.u-307 { padding:3px; margin:14px; border-radius:7px; }
.u-307-bg { background: hsl(349, 50%, 90%); }
.u-307-fg { color: hsl(137, 30%, 25%); }
.u-308 { padding:4px; margin:16px; border-radius:8px; }
.u-308-bg { background: hsl(356, 50%, 90%); }
.u-308-fg { color: hsl(148, 30%, 25%); }
.u-309 { padding:5px; margin:18px; border-radius:9px; }
.u-309-bg { background: hsl(3, 50%, 90%); }
.u-309-fg { color: hsl(159, 30%, 25%); }
.u-310 { padding:6px; margin:20px; border-radius:10px; }
.u-310-bg { background: hsl(10, 50%, 90%); }
.u-310-fg { color: hsl(170, 30%, 25%); }
.u-311 { padding:7px; margin:22px; border-radius:11px; }
.u-311-bg { background: hsl(17, 50%, 90%); }
.u-311-fg { color: hsl(181, 30%, 25%); }
.u-312 { padding:8px; margin:0px; border-radius:0px; }
.u-312-bg { background: hsl(24, 50%, 90%); }
.u-312-fg { color: hsl(192, 30%, 25%); }
.u-313 { padding:9px; margin:2px; border-radius:1px; }
.u-313-bg { background: hsl(31, 50%, 90%); }
.u-313-fg { color: hsl(203, 30%, 25%); }
.u-314 { padding:10px; margin:4px; border-radius:2px; }
.u-314-bg { background: hsl(38, 50%, 90%); }
.u-314-fg { color: hsl(214, 30%, 25%); }
.u-315 { padding:11px; margin:6px; border-radius:3px; }
.u-315-bg { background: hsl(45, 50%, 90%); }
.u-315-fg { color: hsl(225, 30%, 25%); }
.u-316 { padding:12px; margin:8px; border-radius:4px; }
.u-316-bg { background: hsl(52, 50%, 90%); }
.u-316-fg { color: hsl(236, 30%, 25%); }
.u-317 { padding:13px; margin:10px; border-radius:5px; }
.u-317-bg { background: hsl(59, 50%, 90%); }
.u-317-fg { color: hsl(247, 30%, 25%); }
.u-318 { padding:14px; margin:12px; border-radius:6px; }
.u-318-bg { background: hsl(66, 50%, 90%); }
.u-318-fg { color: hsl(258, 30%, 25%); }
.u-319 { padding:15px; margin:14px; border-radius:7px; }
.u-319-bg { background: hsl(73, 50%, 90%); }
.u-319-fg { color: hsl(269, 30%, 25%); }
.u-320 { padding:0px; margin:16px; border-radius:8px; }
.u-320-bg { background: hsl(80, 50%, 90%); }
.u-320-fg { color: hsl(280, 30%, 25%); }
.u-321 { padding:1px; margin:18px; border-radius:9px; }
.u-321-bg { background: hsl(87, 50%, 90%); }
.u-321-fg { color: hsl(291, 30%, 25%); }
.u-322 { padding:2px; margin:20px; border-radius:10px; }
.u-322-bg { background: hsl(94, 50%, 90%); }
.u-322-fg { color: hsl(302, 30%, 25%); }
.u-323 { padding:3px; margin:22px; border-radius:11px; }
.u-323-bg { background: hsl(101, 50%, 90%); }
.u-323-fg { color: hsl(313, 30%, 25%); }
.u-324 { padding:4px; margin:0px; border-radius:0px; }
.u-324-bg { background: hsl(108, 50%, 90%); }
.u-324-fg { color: hsl(324, 30%, 25%); }
.u-325 { padding:5px; margin:2px; border-radius:1px; }
.u-325-bg { background: hsl(115, 50%, 90%); }
.u-325-fg { color: hsl(335, 30%, 25%); }
.u-326 { padding:6px; margin:4px; border-radius:2px; }
.u-326-bg { background: hsl(122, 50%, 90%); }
.u-326-fg { color: hsl(346, 30%, 25%); }
.u-327 { padding:7px; margin:6px; border-radius:3px; }
.u-327-bg { background: hsl(129, 50%, 90%); }
.u-327-fg { color: hsl(357, 30%, 25%); }
.u-328 { padding:8px; margin:8px; border-radius:4px; }
.u-328-bg { background: hsl(136, 50%, 90%); }
.u-328-fg { color: hsl(8, 30%, 25%); }
.u-329 { padding:9px; margin:10px; border-radius:5px; }
.u-329-bg { background: hsl(143, 50%, 90%); }
.u-329-fg { color: hsl(19, 30%, 25%); }
.u-330 { padding:10px; margin:12px; border-radius:6px; }
.u-330-bg { background: hsl(150, 50%, 90%); }
.u-330-fg { color: hsl(30, 30%, 25%); }
.u-331 { padding:11px; margin:14px; border-radius:7px; }
.u-331-bg { background: hsl(157, 50%, 90%); }
.u-331-fg { color: hsl(41, 30%, 25%); }
.u-332 { padding:12px; margin:16px; border-radius:8px; }
.u-332-bg { background: hsl(164, 50%, 90%); }
.u-332-fg { color: hsl(52, 30%, 25%); }
.u-333 { padding:13px; margin:18px; border-radius:9px; }
.u-333-bg { background: hsl(171, 50%, 90%); }
.u-333-fg { color: hsl(63, 30%, 25%); }
.u-334 { padding:14px; margin:20px; border-radius:10px; }
.u-334-bg { background: hsl(178, 50%, 90%); }
.u-334-fg { color: hsl(74, 30%, 25%); }
.u-335 { padding:15px; margin:22px; border-radius:11px; }
.u-335-bg { background: hsl(185, 50%, 90%); }
.u-335-fg { color: hsl(85, 30%, 25%); }
.u-336 { padding:0px; margin:0px; border-radius:0px; }
.u-336-bg { background: hsl(192, 50%, 90%); }
.u-336-fg { color: hsl(96, 30%, 25%); }
.u-337 { padding:1px; margin:2px; border-radius:1px; }
.u-337-bg { background: hsl(199, 50%, 90%); }
.u-337-fg { color: hsl(107, 30%, 25%); }
.u-338 { padding:2px; margin:4px; border-radius:2px; }
.u-338-bg { background: hsl(206, 50%, 90%); }
.u-338-fg { color: hsl(118, 30%, 25%); }
.u-339 { padding:3px; margin:6px; border-radius:3px; }
.u-339-bg { background: hsl(213, 50%, 90%); }
.u-339-fg { color: hsl(129, 30%, 25%); }
.u-340 { padding:4px; margin:8px; border-radius:4px; }
.u-340-bg { background: hsl(220, 50%, 90%); }
.u-340-fg { color: hsl(140, 30%, 25%); }
.u-341 { padding:5px; margin:10px; border-radius:5px; }
.u-341-bg { background: hsl(227, 50%, 90%); }
.u-341-fg { color: hsl(151, 30%, 25%); }
.u-342 { padding:6px; margin:12px; border-radius:6px; }
.u-342-bg { background: hsl(234, 50%, 90%); }
.u-342-fg { color: hsl(162, 30%, 25%); }
.u-343 { padding:7px; margin:14px; border-radius:7px; }
.u-343-bg { background: hsl(241, 50%, 90%); }
.u-343-fg { color: hsl(173, 30%, 25%); }
.u-344 { padding:8px; margin:16px; border-radius:8px; }
.u-344-bg { background: hsl(248, 50%, 90%); }
.u-344-fg { color: hsl(184, 30%, 25%); }
.u-345 { padding:9px; margin:18px; border-radius:9px; }
.u-345-bg { background: hsl(255, 50%, 90%); }
.u-345-fg { color: hsl(195, 30%, 25%); }
.u-346 { padding:10px; margin:20px; border-radius:10px; }
.u-346-bg { background: hsl(262, 50%, 90%); }
.u-346-fg { color: hsl(206, 30%, 25%); }
.u-347 { padding:11px; margin:22px; border-radius:11px; }
.u-347-bg { background: hsl(269, 50%, 90%); }
.u-347-fg { color: hsl(217, 30%, 25%); }
.u-348 { padding:12px; margin:0px; border-radius:0px; }
.u-348-bg { background: hsl(276, 50%, 90%); }
.u-348-fg { color: hsl(228, 30%, 25%); }
.u-349 { padding:13px; margin:2px; border-radius:1px; }
.u-349-bg { background: hsl(283, 50%, 90%); }
.u-349-fg { color: hsl(239, 30%, 25%); }
.u-350 { padding:14px; margin:4px; border-radius:2px; }
.u-350-bg { background: hsl(290, 50%, 90%); }
.u-350-fg { color: hsl(250, 30%, 25%); }
.u-351 { padding:15px; margin:6px; border-radius:3px; }
.u-351-bg { background: hsl(297, 50%, 90%); }
.u-351-fg { color: hsl(261, 30%, 25%); }
.u-352 { padding:0px; margin:8px; border-radius:4px; }
.u-352-bg { background: hsl(304, 50%, 90%); }
.u-352-fg { color: hsl(272, 30%, 25%); }
.u-353 { padding:1px; margin:10px; border-radius:5px; }
.u-353-bg { background: hsl(311, 50%, 90%); }
.u-353-fg { color: hsl(283, 30%, 25%); }
.u-354 { padding:2px; margin:12px; border-radius:6px; }
.u-354-bg { background: hsl(318, 50%, 90%); }
.u-354-fg { color: hsl(294, 30%, 25%); }
.u-355 { padding:3px; margin:14px; border-radius:7px; }
.u-355-bg { background: hsl(325, 50%, 90%); }
.u-355-fg { color: hsl(305, 30%, 25%); }
.u-356 { padding:4px; margin:16px; border-radius:8px; }
.u-356-bg { background: hsl(332, 50%, 90%); }
.u-356-fg { color: hsl(316, 30%, 25%); }
.u-357 { padding:5px; margin:18px; border-radius:9px; }
.u-357-bg { background: hsl(339, 50%, 90%); }
.u-357-fg { color: hsl(327, 30%, 25%); }
.u-358 { padding:6px; margin:20px; border-radius:10px; }
.u-358-bg { background: hsl(346, 50%, 90%); }
.u-358-fg { color: hsl(338, 30%, 25%); }
.u-359 { padding:7px; margin:22px; border-radius:11px; }
.u-359-bg { background: hsl(353, 50%, 90%); }
.u-359-fg { color: hsl(349, 30%, 25%); }
.u-360 { padding:8px; margin:0px; border-radius:0px; }
.u-360-bg { background: hsl(0, 50%, 90%); }
.u-360-fg { color: hsl(0, 30%, 25%); }
.u-361 { padding:9px; margin:2px; border-radius:1px; }
.u-361-bg { background: hsl(7, 50%, 90%); }
.u-361-fg { color: hsl(11, 30%, 25%); }
.u-362 { padding:10px; margin:4px; border-radius:2px; }
.u-362-bg { background: hsl(14, 50%, 90%); }
.u-362-fg { color: hsl(22, 30%, 25%); }
.u-363 { padding:11px; margin:6px; border-radius:3px; }
.u-363-bg { background: hsl(21, 50%, 90%); }
.u-363-fg { color: hsl(33, 30%, 25%); }
.u-364 { padding:12px; margin:8px; border-radius:4px; }
.u-364-bg { background: hsl(28, 50%, 90%); }
.u-364-fg { color: hsl(44, 30%, 25%); }
.u-365 { padding:13px; margin:10px; border-radius:5px; }
.u-365-bg { background: hsl(35, 50%, 90%); }
.u-365-fg { color: hsl(55, 30%, 25%); }
.u-366 { padding:14px; margin:12px; border-radius:6px; }
.u-366-bg { background: hsl(42, 50%, 90%); }
.u-366-fg { color: hsl(66, 30%, 25%); }
.u-367 { padding:15px; margin:14px; border-radius:7px; }
.u-367-bg { background: hsl(49, 50%, 90%); }
.u-367-fg { color: hsl(77, 30%, 25%); }
.u-368 { padding:0px; margin:16px; border-radius:8px; }
.u-368-bg { background: hsl(56, 50%, 90%); }
.u-368-fg { color: hsl(88, 30%, 25%); }
.u-369 { padding:1px; margin:18px; border-radius:9px; }
.u-369-bg { background: hsl(63, 50%, 90%); }
.u-369-fg { color: hsl(99, 30%, 25%); }
.u-370 { padding:2px; margin:20px; border-radius:10px; }
.u-370-bg { background: hsl(70, 50%, 90%); }
.u-370-fg { color: hsl(110, 30%, 25%); }
.u-371 { padding:3px; margin:22px; border-radius:11px; }
.u-371-bg { background: hsl(77, 50%, 90%); }
.u-371-fg { color: hsl(121, 30%, 25%); }
.u-372 { padding:4px; margin:0px; border-radius:0px; }
.u-372-bg { background: hsl(84, 50%, 90%); }
.u-372-fg { color: hsl(132, 30%, 25%); }
.u-373 { padding:5px; margin:2px; border-radius:1px; }
.u-373-bg { background: hsl(91, 50%, 90%); }
.u-373-fg { color: hsl(143, 30%, 25%); }
.u-374 { padding:6px; margin:4px; border-radius:2px; }
.u-374-bg { background: hsl(98, 50%, 90%); }
.u-374-fg { color: hsl(154, 30%, 25%); }
.u-375 { padding:7px; margin:6px; border-radius:3px; }
.u-375-bg { background: hsl(105, 50%, 90%); }
.u-375-fg { color: hsl(165, 30%, 25%); }
.u-376 { padding:8px; margin:8px; border-radius:4px; }
.u-376-bg { background: hsl(112, 50%, 90%); }
.u-376-fg { color: hsl(176, 30%, 25%); }
.u-377 { padding:9px; margin:10px; border-radius:5px; }
.u-377-bg { background: hsl(119, 50%, 90%); }
.u-377-fg { color: hsl(187, 30%, 25%); }
.u-378 { padding:10px; margin:12px; border-radius:6px; }
.u-378-bg { background: hsl(126, 50%, 90%); }
.u-378-fg { color: hsl(198, 30%, 25%); }
.u-379 { padding:11px; margin:14px; border-radius:7px; }
.u-379-bg { background: hsl(133, 50%, 90%); }
.u-379-fg { color: hsl(209, 30%, 25%); }
.u-380 { padding:12px; margin:16px; border-radius:8px; }
.u-380-bg { background: hsl(140, 50%, 90%); }
.u-380-fg { color: hsl(220, 30%, 25%); }
.u-381 { padding:13px; margin:18px; border-radius:9px; }
.u-381-bg { background: hsl(147, 50%, 90%); }
.u-381-fg { color: hsl(231, 30%, 25%); }
.u-382 { padding:14px; margin:20px; border-radius:10px; }
.u-382-bg { background: hsl(154, 50%, 90%); }
.u-382-fg { color: hsl(242, 30%, 25%); }
.u-383 { padding:15px; margin:22px; border-radius:11px; }
.u-383-bg { background: hsl(161, 50%, 90%); }
.u-383-fg { color: hsl(253, 30%, 25%); }
.u-384 { padding:0px; margin:0px; border-radius:0px; }
.u-384-bg { background: hsl(168, 50%, 90%); }
.u-384-fg { color: hsl(264, 30%, 25%); }
.u-385 { padding:1px; margin:2px; border-radius:1px; }
.u-385-bg { background: hsl(175, 50%, 90%); }
.u-385-fg { color: hsl(275, 30%, 25%); }
.u-386 { padding:2px; margin:4px; border-radius:2px; }
.u-386-bg { background: hsl(182, 50%, 90%); }
.u-386-fg { color: hsl(286, 30%, 25%); }
.u-387 { padding:3px; margin:6px; border-radius:3px; }
.u-387-bg { background: hsl(189, 50%, 90%); }
.u-387-fg { color: hsl(297, 30%, 25%); }
.u-388 { padding:4px; margin:8px; border-radius:4px; }
.u-388-bg { background: hsl(196, 50%, 90%); }
.u-388-fg { color: hsl(308, 30%, 25%); }
.u-389 { padding:5px; margin:10px; border-radius:5px; }
.u-389-bg { background: hsl(203, 50%, 90%); }
.u-389-fg { color: hsl(319, 30%, 25%); }
.u-390 { padding:6px; margin:12px; border-radius:6px; }
.u-390-bg { background: hsl(210, 50%, 90%); }
.u-390-fg { color: hsl(330, 30%, 25%); }
.u-391 { padding:7px; margin:14px; border-radius:7px; }
.u-391-bg { background: hsl(217, 50%, 90%); }
.u-391-fg { color: hsl(341, 30%, 25%); }
.u-392 { padding:8px; margin:16px; border-radius:8px; }
.u-392-bg { background: hsl(224, 50%, 90%); }
.u-392-fg { color: hsl(352, 30%, 25%); }
.u-393 { padding:9px; margin:18px; border-radius:9px; }
.u-393-bg { background: hsl(231, 50%, 90%); }
.u-393-fg { color: hsl(3, 30%, 25%); }
.u-394 { padding:10px; margin:20px; border-radius:10px; }
.u-394-bg { background: hsl(238, 50%, 90%); }
.u-394-fg { color: hsl(14, 30%, 25%); }
.u-395 { padding:11px; margin:22px; border-radius:11px; }
.u-395-bg { background: hsl(245, 50%, 90%); }
.u-395-fg { color: hsl(25, 30%, 25%); }
.u-396 { padding:12px; margin:0px; border-radius:0px; }
.u-396-bg { background: hsl(252, 50%, 90%); }
.u-396-fg { color: hsl(36, 30%, 25%); }
.u-397 { padding:13px; margin:2px; border-radius:1px; }
.u-397-bg { background: hsl(259, 50%, 90%); }
.u-397-fg { color: hsl(47, 30%, 25%); }
.u-398 { padding:14px; margin:4px; border-radius:2px; }
.u-398-bg { background: hsl(266, 50%, 90%); }
.u-398-fg { color: hsl(58, 30%, 25%); }
.u-399 { padding:15px; margin:6px; border-radius:3px; }
.u-399-bg { background: hsl(273, 50%, 90%); }
.u-399-fg { color: hsl(69, 30%, 25%); }
.u-400 { padding:0px; margin:8px; border-radius:4px; }
.u-400-bg { background: hsl(280, 50%, 90%); }
.u-400-fg { color: hsl(80, 30%, 25%); }
}
```

### 8.2 WASM Bootstrap Stub (TypeScript)
```ts
// wasm_bootstrap.ts (reference stub)
export async function bootWasm(opts: {
  src: string;
  mount: string;
  config?: any;
}) {
  const canvas = document.querySelector(opts.mount) as HTMLCanvasElement | null;
  if (!canvas) throw new Error("Mount not found: " + opts.mount);

  const { instance } = await WebAssembly.instantiateStreaming(fetch(opts.src), {});
  const init = instance.exports.init as Function | undefined;
  const step = instance.exports.step as Function | undefined;
  const render = instance.exports.render as Function | undefined;

  if (init) init(opts.config ?? {});

  let t = 0;
  function frame(ts: number) {
    const dt = ts - t;
    t = ts;
    if (step) step(dt);
    if (render) render();
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}
```

#### Variant 2: different mount/config handling
```ts
// wasm_bootstrap.ts (reference stub)
export async function bootWasm(opts: {
  src: string;
  mount: string;
  config?: any;
}) {
  const canvas = document.querySelector(opts.mount /*v2*/) as HTMLCanvasElement | null;
  if (!canvas) throw new Error("Mount not found: " + opts.mount /*v2*/);

  const { instance } = await WebAssembly.instantiateStreaming(fetch(opts.src), {});
  const init = instance.exports.init as Function | undefined;
  const step = instance.exports.step as Function | undefined;
  const render = instance.exports.render as Function | undefined;

  if (init) init(opts.config ?? {});

  let t = 0;
  function frame(ts: number) {
    const dt = ts - t;
    t = ts;
    if (step) step(dt);
    if (render) render();
    requestAnimationFrame /*v2*/(frame);
  }
  requestAnimationFrame /*v2*/(frame);
}
```

#### Variant 3: different mount/config handling
```ts
// wasm_bootstrap.ts (reference stub)
export async function bootWasm(opts: {
  src: string;
  mount: string;
  config?: any;
}) {
  const canvas = document.querySelector(opts.mount /*v3*/) as HTMLCanvasElement | null;
  if (!canvas) throw new Error("Mount not found: " + opts.mount /*v3*/);

  const { instance } = await WebAssembly.instantiateStreaming(fetch(opts.src), {});
  const init = instance.exports.init as Function | undefined;
  const step = instance.exports.step as Function | undefined;
  const render = instance.exports.render as Function | undefined;

  if (init) init(opts.config ?? {});

  let t = 0;
  function frame(ts: number) {
    const dt = ts - t;
    t = ts;
    if (step) step(dt);
    if (render) render();
    requestAnimationFrame /*v3*/(frame);
  }
  requestAnimationFrame /*v3*/(frame);
}
```

#### Variant 4: different mount/config handling
```ts
// wasm_bootstrap.ts (reference stub)
export async function bootWasm(opts: {
  src: string;
  mount: string;
  config?: any;
}) {
  const canvas = document.querySelector(opts.mount /*v4*/) as HTMLCanvasElement | null;
  if (!canvas) throw new Error("Mount not found: " + opts.mount /*v4*/);

  const { instance } = await WebAssembly.instantiateStreaming(fetch(opts.src), {});
  const init = instance.exports.init as Function | undefined;
  const step = instance.exports.step as Function | undefined;
  const render = instance.exports.render as Function | undefined;

  if (init) init(opts.config ?? {});

  let t = 0;
  function frame(ts: number) {
    const dt = ts - t;
    t = ts;
    if (step) step(dt);
    if (render) render();
    requestAnimationFrame /*v4*/(frame);
  }
  requestAnimationFrame /*v4*/(frame);
}
```

#### Variant 5: different mount/config handling
```ts
// wasm_bootstrap.ts (reference stub)
export async function bootWasm(opts: {
  src: string;
  mount: string;
  config?: any;
}) {
  const canvas = document.querySelector(opts.mount /*v5*/) as HTMLCanvasElement | null;
  if (!canvas) throw new Error("Mount not found: " + opts.mount /*v5*/);

  const { instance } = await WebAssembly.instantiateStreaming(fetch(opts.src), {});
  const init = instance.exports.init as Function | undefined;
  const step = instance.exports.step as Function | undefined;
  const render = instance.exports.render as Function | undefined;

  if (init) init(opts.config ?? {});

  let t = 0;
  function frame(ts: number) {
    const dt = ts - t;
    t = ts;
    if (step) step(dt);
    if (render) render();
    requestAnimationFrame /*v5*/(frame);
  }
  requestAnimationFrame /*v5*/(frame);
}
```

## 9. Complete Example Documents

### Example A — Minimal Styles, Links, Code, Math, WASM

```dcz
@styledef{
  note = "rounded bg-yellow-50 px-2"
  callout = "rounded-md border p-4 bg-blue-50"
}

# Luma — Volume 1
See [Zig](https://ziglang.org) and `@import("std")`. Einstein said $E = mc^2$.

@(name="note"){Inline alias style}

@style(class="color = red") red span @end then regular text.
```

```zig
const std = @import("std");
pub fn main() !void { _ = std.heap.page_allocator; }
```

```dcz
@css{
  .docz-body { line-height: 1.55; }
}

@wasm(src="wasm/luma.wasm", funcs="init,step,render", mount="#app"){
  <canvas id="app" width="640" height="480" aria-label="Luma demo canvas"></canvas>
}
```

### Example B1 — Aliases, Blocks, Media, and Actions

```sh
@styledef{  alias1_0 = "p-2 rounded bg-gray-50"  alias1_1 = "p-2 rounded bg-gray-100"  alias1_2 = "p-2 rounded bg-gray-150"}
# Section Heading
Paragraph with `inline code` and a [link](https://example.com). Einstein: $E=mc^2$.
@(name="alias1_0", on-click="copy"){Click to copy alias 1_0}
@style(class="color = green") greened @end and text.
```

```zig
const v = 42;
```
@css{ .box { padding: 8px; } }
@wasm(src="wasm/demo1.wasm", funcs="init,step,render", mount="#m1"){
  <canvas id="m1" width="320" height="180" aria-label="demo 1"></canvas>
}
@style(classes="rounded bg-gray-50 p-2"){
Image below
}
@style(classes="text-xs text-gray-600"){
Caption: sample
}
```

### Example B2 — Aliases, Blocks, Media, and Actions
```dcz
@styledef{  alias2_0 = "p-2 rounded bg-gray-50"  alias2_1 = "p-2 rounded bg-gray-100"  alias2_2 = "p-2 rounded bg-gray-150"}
# Section Heading
Paragraph with `inline code` and a [link](https://example.com). Einstein: $E=mc^2$.
@(name="alias2_0", on-click="copy"){Click to copy alias 2_0}
@style(class="color = green") greened @end and text.
```zig
const v = 42;
```
@css{ .box { padding: 8px; } }
@wasm(src="wasm/demo2.wasm", funcs="init,step,render", mount="#m2"){
  <canvas id="m2" width="320" height="180" aria-label="demo 2"></canvas>
}
@style(classes="rounded bg-gray-50 p-2"){
Image below
}
@style(classes="text-xs text-gray-600"){
Caption: sample
}
```

### Example B3 — Aliases, Blocks, Media, and Actions
```dcz
@styledef{  alias3_0 = "p-2 rounded bg-gray-50"  alias3_1 = "p-2 rounded bg-gray-100"  alias3_2 = "p-2 rounded bg-gray-150"}
# Section Heading
Paragraph with `inline code` and a [link](https://example.com). Einstein: $E=mc^2$.
@(name="alias3_0", on-click="copy"){Click to copy alias 3_0}
@style(class="color = green") greened @end and text.
```zig
const v = 42;
```
@css{ .box { padding: 8px; } }
@wasm(src="wasm/demo3.wasm", funcs="init,step,render", mount="#m3"){
  <canvas id="m3" width="320" height="180" aria-label="demo 3"></canvas>
}
@style(classes="rounded bg-gray-50 p-2"){
Image below
}
@style(classes="text-xs text-gray-600"){
Caption: sample
}
```

### Example B4 — Aliases, Blocks, Media, and Actions
```dcz
@styledef{  alias4_0 = "p-2 rounded bg-gray-50"  alias4_1 = "p-2 rounded bg-gray-100"  alias4_2 = "p-2 rounded bg-gray-150"}
# Section Heading
Paragraph with `inline code` and a [link](https://example.com). Einstein: $E=mc^2$.
@(name="alias4_0", on-click="copy"){Click to copy alias 4_0}
@style(class="color = green") greened @end and text.
```zig
const v = 42;
```
@css{ .box { padding: 8px; } }
@wasm(src="wasm/demo4.wasm", funcs="init,step,render", mount="#m4"){
  <canvas id="m4" width="320" height="180" aria-label="demo 4"></canvas>
}
@style(classes="rounded bg-gray-50 p-2"){
Image below
}
@style(classes="text-xs text-gray-600"){
Caption: sample
}
```

### Example B5 — Aliases, Blocks, Media, and Actions
```dcz
@styledef{  alias5_0 = "p-2 rounded bg-gray-50"  alias5_1 = "p-2 rounded bg-gray-100"  alias5_2 = "p-2 rounded bg-gray-150"}
# Section Heading
Paragraph with `inline code` and a [link](https://example.com). Einstein: $E=mc^2$.
@(name="alias5_0", on-click="copy"){Click to copy alias 5_0}
@style(class="color = green") greened @end and text.
```zig
const v = 42;
```
@css{ .box { padding: 8px; } }
@wasm(src="wasm/demo5.wasm", funcs="init,step,render", mount="#m5"){
  <canvas id="m5" width="320" height="180" aria-label="demo 5"></canvas>
}
@style(classes="rounded bg-gray-50 p-2"){
Image below
}
@style(classes="text-xs text-gray-600"){
Caption: sample
}
```

## 10. Inline Edge Cases — Extended Gallery
Below, we repeat key transformations across many variations to make behavior unmistakable.

```text
(Expect literal arrows to indicate → outputs in prose; actual renderer produces HTML.)
```

**Case 1.A**  
The @style(class=color = red) preview @end server.

**Case 1.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 1.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 2.A**  
The @style(class=color = red) preview @end server.

**Case 2.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 2.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 3.A**  
The @style(class=color = red) preview @end server.

**Case 3.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 3.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 4.A**  
The @style(class=color = red) preview @end server.

**Case 4.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 4.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 5.A**  
The @style(class=color = red) preview @end server.

**Case 5.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 5.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 6.A**  
The @style(class=color = red) preview @end server.

**Case 6.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 6.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 7.A**  
The @style(class=color = red) preview @end server.

**Case 7.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 7.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 8.A**  
The @style(class=color = red) preview @end server.

**Case 8.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 8.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 9.A**  
The @style(class=color = red) preview @end server.

**Case 9.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 9.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 10.A**  
The @style(class=color = red) preview @end server.

**Case 10.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 10.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 11.A**  
The @style(class=color = red) preview @end server.

**Case 11.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 11.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 12.A**  
The @style(class=color = red) preview @end server.

**Case 12.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 12.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 13.A**  
The @style(class=color = red) preview @end server.

**Case 13.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 13.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 14.A**  
The @style(class=color = red) preview @end server.

**Case 14.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 14.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 15.A**  
The @style(class=color = red) preview @end server.

**Case 15.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 15.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 16.A**  
The @style(class=color = red) preview @end server.

**Case 16.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 16.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 17.A**  
The @style(class=color = red) preview @end server.

**Case 17.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 17.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 18.A**  
The @style(class=color = red) preview @end server.

**Case 18.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 18.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 19.A**  
The @style(class=color = red) preview @end server.

**Case 19.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 19.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 20.A**  
The @style(class=color = red) preview @end server.

**Case 20.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 20.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 21.A**  
The @style(class=color = red) preview @end server.

**Case 21.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 21.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 22.A**  
The @style(class=color = red) preview @end server.

**Case 22.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 22.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 23.A**  
The @style(class=color = red) preview @end server.

**Case 23.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 23.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 24.A**  
The @style(class=color = red) preview @end server.

**Case 24.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 24.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 25.A**  
The @style(class=color = red) preview @end server.

**Case 25.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 25.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 26.A**  
The @style(class=color = red) preview @end server.

**Case 26.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 26.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 27.A**  
The @style(class=color = red) preview @end server.

**Case 27.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 27.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 28.A**  
The @style(class=color = red) preview @end server.

**Case 28.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 28.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 29.A**  
The @style(class=color = red) preview @end server.

**Case 29.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 29.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 30.A**  
The @style(class=color = red) preview @end server.

**Case 30.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 30.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 31.A**  
The @style(class=color = red) preview @end server.

**Case 31.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 31.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 32.A**  
The @style(class=color = red) preview @end server.

**Case 32.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 32.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 33.A**  
The @style(class=color = red) preview @end server.

**Case 33.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 33.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 34.A**  
The @style(class=color = red) preview @end server.

**Case 34.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 34.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 35.A**  
The @style(class=color = red) preview @end server.

**Case 35.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 35.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 36.A**  
The @style(class=color = red) preview @end server.

**Case 36.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 36.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 37.A**  
The @style(class=color = red) preview @end server.

**Case 37.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 37.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 38.A**  
The @style(class=color = red) preview @end server.

**Case 38.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 38.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 39.A**  
The @style(class=color = red) preview @end server.

**Case 39.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 39.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

**Case 40.A**  
The @style(class=color = red) preview @end server.

**Case 40.B**  
@(class=text-red-500 underline){danger} and `code` with [link](https://ziglang.org).

**Case 40.C**  
Use \$E=mc^2\$ intact; `backticks` should escape < & >, and \(ignored parens\).

## 11. Exporter Utilities (for CLI convenience)

Tooling may expect these helpers from the HTML exporter module:

- `collectInlineCss(doc: *ASTNode, A) ![]u8`  
  Returns a single CSS string collected from `Css` blocks (implementation-dependent).

- `stripFirstStyleBlock(html: []const u8, A) ![]u8`  
  Returns the HTML with the first `<style>…</style>` removed. (Used when the CLI emits CSS separately.)

These are **conveniences** and can be no-ops for minimal builds, as long as the CLI guards for absence.

## 12. Conformance & Future Extensions

- Documents and tooling that follow the above **must** preserve math `$...$` inline, apply style span rules,
  escape code spans, and implement the alias resolution.  
- Future extensions may add new directives (e.g., `@graph`, `@table`, `@data`), richer WASM lifecycles, and
  stricter URL/integrity policies for `@import`.

---

**End of Gold Verbatim Edition.**  
If you need an **even larger** corpus (e.g., to approximate real-world `.dcz` payload sizes), duplicate
the Example Documents section and expand the CSS payload. This edition already includes long, verbatim-like blocks
and 40× repeated inline edge cases to serve as an authoritative reference and training seed.
