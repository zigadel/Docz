# Docz File Specification (DCZ) — **GOLD / Canonical Flow**

> **Purpose.** This document is the reader‑ and model‑friendly single source of truth for writing `.dcz` files. It is ordered for learning, precise enough for generation, and faithful to the current Docz parser + HTML exporter behavior you’ve implemented (as validated by tests we’ve discussed).  
> **Audience.** Humans authoring DCZ, and LLMs generating DCZ.  
> **Scope.** All syntax and semantics: block & inline constructs, directives, style system, KaTeX, Tailwind, WASM embedding, escaping rules, and how free text becomes HTML.  
> **Status.** Canonical, forward-compatible; if your code deviates, update either the code or this spec—**not** both.

---

## 0) Quick mental model

A `.dcz` file is a linear text format that Docz parses into a simple AST:

- **Document** (root)
  - **Meta** (key/value metadata used by build/export)
  - **Heading** (level 1–6 → `<h1>`…`<h6>`)
  - **Content** (paragraph-like inline text → `<p>…</p>`)
  - **CodeBlock** (verbatim code → `<pre><code>…</code></pre>`)
  - **Math** (explicit math block; inline math is handled in Content)
  - **Media** (images, etc.)
  - **Style** and **StyleDef** (styling aliases + style blocks)
  - **Css** and **Import** (assets/bootstrap handled by CLI/export pipeline)

**Key rule:** “Random text” (free text not part of another block) becomes **Content** → rendered as `<p>…</p>`. There is **no implicit `<section>`** wrapping. If you want sections, write headings and/or a section directive yourself.

**Inline transformation** happens inside **Content** nodes (paragraphs) by the inline renderer:
- Markdown-style links: `[text](url)`
- Backtick code spans: `` `code` `` → `<code>code</code>`
- Inline style directives (two forms): `@style(...) … @end` and `@(…) { … }`
- Preserves KaTeX delimiters `$...$` (inline) for auto-render later
- Leaves plain text alone (minus needed HTML escaping inside code spans/attributes)

---

## 1) File structure & block repertoire

### 1.1 Minimal file

```dcz
@meta(key="title", value="Hello Docz")

# Introduction

Welcome to Docz! This is a paragraph.

- You can write lists in plain text if your theme supports it (Docz will emit as paragraphs unless your pipeline extends list parsing).

```

```
3x backticks (backticks fence; see §2.3)
```

> **Note:** The parser treats “free text” lines as **Content** until a block boundary (heading, code fence, explicit directive, etc.).

### 1.2 Headings

Write headings using `#` prefix (1–6). Exporter renders `<h1>`…`<h6>`.

```dcz
# H1 Title
## H2 Section
### H3 Subsection
```

### 1.3 Paragraphs (Content)

Any line(s) of free text produce **Content** nodes rendered as `<p>…</p>`. Example:

```dcz
This is a paragraph with an [inline link](https://ziglang.org) and `code`.
```

### 1.4 Code blocks

Use triple-backtick fences. Optional language tag is passed through (for your highlighter pipeline to use).

```dcz
```zig
const std = @import("std");
\```
```

Renders as:

```html
<pre><code class="language-zig">const std = @import(&quot;std&quot;);</code></pre>
```

> Exporter escapes HTML characters inside code content, preserving literal text.

### 1.5 Math (block & inline)

- **Inline math**: `$ ... $` inside Content is **preserved** verbatim. KaTeX auto-render finds and renders it in the browser. Example:

  ```dcz
  Einstein wrote $E = mc^2$.
  ```

- **Block math**: either fenced `$$` blocks or an explicit Math block (depending on your parser’s support). The exporter emits a container that KaTeX can render:

  ```dcz
  $$
  \int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
  $$
  ```

  Exporter output (representative):

  ```html
  <div class="math">$$\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$$</div>
  ```

> **Always enabled:** KaTeX auto-render is included in Docz preview/build. Do **not** escape `$` in Content unless you mean a literal dollar; the inline renderer intentionally leaves `$...$` untouched.

### 1.6 Media (images)

Use a media directive or an import/asset path that your loader serves. Canonical minimal inline form:

```dcz
@img(src="/img/logo.png")
```

Exporter emits:

```html
<img src="/img/logo.png" />
```

You may prefer the more general **Media** directive with alt, width, height, classes, etc. (see §3.3).

### 1.7 CSS & Imports

Use `@css` to include CSS text, `@import` for files/URLs. These are queued by the pipeline and injected in `<head>` (or bundled depending on build flags).

```dcz
@css { 
  /* custom tweaks */
  .note { background: #fffbcc; padding: 0.5rem; }
}

@import(href="/third_party/katex/0.16.22/dist/katex.min.css")
```

---

## 2) Inline syntax in paragraphs (Content)

The inline renderer (used by exporter for Content) performs the following transformations **in order**:

1. **Backtick code spans**  
   - Input: ``some `inline code` here``  
   - Output: `some <code>inline code</code> here`  
   - HTML is escaped inside `<code>`.

2. **Inline style rewrite** (two notations; see §2.1–§2.2, §4)  
   - Shorthand: `@(attrs) { body }`  
   - Explicit: `@style(attrs) body @end`  
   - Both produce `<span ...>body</span>` with attributes resolved/merged/escaped.

3. **Markdown links**  
   - `[Zig](https://ziglang.org)` → `<a href="https://ziglang.org">Zig</a>`  
   - Simple heuristic for “URL-ish” strings is used; otherwise literal text preserved.

4. **KaTeX inline math** is **not** touched (left as `$ ... $` for client-side KaTeX).

### 2.1 Shorthand inline style: `@(…) { … }`

```dcz
@(class="text-red-600"){warning}
```

→

```html
<span class="text-red-600">warning</span>
```

Notes:

- Attributes are parsed from the `(...)` list (see §4.1 Attribute grammar).  
- The body is the braced content and may contain quotes and nested braces; the parser is quote- and brace-aware.  
- You may supply `name="alias"` to resolve a style alias (see §4.3 Style aliases).

### 2.2 Explicit inline style: `@style(…) … @end`

```dcz
The @style(class="color = red") preview @end server.
```

→

```html
The <span style="color = red">preview </span> server.
```

**Class → style heuristic.** If the `class` (or `classes`) attribute **looks like CSS** (contains `:`, `;`, or `=`), Docz treats it as **inline CSS** and emits it as `style="..."`. This is intentional to let authors write short CSS in “class” while still supporting Tailwind (see §5).

Examples:

```dcz
@style(class="font-bold"){Strong}
@style(class="color: red; font-weight: 600"){Red + bold}
@style(classes="color = red") text @end
```

### 2.3 Backtick code spans

- Single backticks only in inline renderer (triple backticks are block fences).  
- Inside code spans, HTML is escaped (`<`, `>`, `&`, quotes).  
- Escapes: you may write `\`` to produce a literal backtick. `\$` is also passed through literally.

### 2.4 Links

- `[label](https://host/path)` → `<a href="...">label</a>`  
- No title attribute parsing in the inline renderer; add as a style if needed:
  `@(class="underline"){[label](url)}`

---

## 3) Block directives (top-level)

Docz supports simple `@name(args) { body }` or `@name(args) … @end` forms. A few canonical ones:

### 3.1 `@meta(...)`

Document metadata. Recognized common keys: `title`, `author`, `date`, `lang`, `description`. Extra keys are passed through to the pipeline and may be exported into HTML head/meta as configured.

```dcz
@meta(key="title", value="My Docz Page")
@meta(key="lang",  value="en")
@meta(key="description", value="Short description for SEO/social.")
```

### 3.2 `@css { … }`

Embed CSS in the document. The CLI/exporter may inline or extract it depending on build flags.

```dcz
@css {
  .callout { border-left: 4px solid #0ea5e9; padding: .75rem 1rem; }
}
```

### 3.3 `@img(...)` and `@media(...) { … }`

Minimal image usage:

```dcz
@img(src="/img/logo.png", alt="Logo", class="mx-auto h-10")
```

General media region:

```dcz
@media(src="/video/intro.mp4", type="video", controls="true") { 
  (optional fallback text) 
}
```

### 3.4 `@import(href=…)`

Add a CSS/JS asset by URL or relative path. In preview, assets are served; in build, the pipeline locks/verifies vendor versions (per your vendor tool).

```dcz
@import(href="/third_party/katex/0.16.22/dist/katex.min.css")
@import(href="/third_party/katex/0.16.22/dist/katex.min.js")
```

### 3.5 `@wasm(...) { … }`

Embed a WASM module with optional mount body (e.g., a `<canvas>`). Docz doesn’t prescribe a single runtime; you can standardize on your loader (e.g., instantiate, pass imports, then attach to an element).

```dcz
@wasm(
  name="pendulum",
  src="/wasm/pendulum.wasm",
  runtime="auto",
  mount="#sim1",
  memory="64MiB"
) {
  <div id="sim1" class="w-full h-64 border rounded"></div>
}
```

Exporter behavior is to emit the body verbatim (HTML allowed) and attach declarative attributes as `data-*` on a wrapping element or emit a script snippet depending on your loader. (Customize in your exporter/runtime glue.)

> For smaller snippets, you may inline WASM as a base64 data URL via `src="data:application/wasm;base64,..."` but prefer external files for caching.

---

## 4) Styling system (inline, aliases, Tailwind, CSS rules)

### 4.1 Attribute grammar in `(...)`

Attributes accept `key="value"` pairs separated by **commas and/or spaces**:

```
key="value"
key='value'
key = "value"
key:value          (colon allowed and treated like '=' for convenience)
name="note" class="rounded bg-yellow-50"
```

- Quotes inside attribute values can be written as HTML entities (`&quot;`), which Docz decodes to `"`.  
- Unknown keys are ignored by the core and may be used by plugins (`data-*` at export time).

**Special inline attributes supported by the renderer:**

| Key          | Meaning                                                                                 |
|--------------|------------------------------------------------------------------------------------------|
| `name`       | Style alias to resolve to classes (see §4.3).                                            |
| `class`/`classes` | Tailwind or regular class list **OR** small CSS snippet (heuristic)                    |
| `style`      | Raw CSS string; merged with class-as-CSS when both present.                              |
| `on-click`   | Action data; exported as `data-on-click="..."`.                                         |
| `on-hover`   | Action data; exported as `data-on-hover="..."`.                                         |
| `on-focus`   | Action data; exported as `data-on-focus="..."`.                                         |

### 4.2 Class‑as‑CSS heuristic

If a `class`/`classes` value **contains any of** `':'`, `';'`, or `'='`, Docz treats it as **CSS** and emits it as `style="…"`. Examples that become `style`:

```
class="color: red"
classes="font-weight = 600"
classes="color: red; font-weight: 600"
```

Examples that remain true `class="…"`:

```
class="text-green-500 underline"
class="mx-auto px-4 sm:px-6 lg:px-8"
```

If `style="…"` is also present, it **merges**: `existing; new`.

### 4.3 Style aliases (`StyleDef` and `name="…"`)  

Define aliases near the top of your doc for reuse:

```dcz
@styledef {
  note = "rounded bg-yellow-50 px-2 py-1 text-yellow-900"
  danger = "bg-red-50 text-red-700 px-2 rounded"
}
```

Use them inline via `name="alias"` (or `class="…"`, which bypasses alias lookup):

```dcz
@(name="note"){Heads up!}
```

→

```html
<span class="rounded bg-yellow-50 px-2 py-1 text-yellow-900">Heads up!</span>
```

### 4.4 Tailwind (optional but first-class)

When Tailwind is **enabled** for your build/preview:

- `class="…" / classes="…"` values that are **not** treated as CSS are passed through to HTML `class` and Tailwind styles apply.  
- You may also import your preferred Tailwind build via `@import(href="...")` if you need a different version than Docz’s default.

**Example:**

```dcz
@(class="text-green-500 font-semibold"){Success}
```

---

## 5) Escaping rules & entity handling

- Text content is **not** decoded for HTML entities (e.g., `&quot;` stays `&quot;`) so that authors can include literal HTML safely.  
- Attribute values inside `(...)` **do decode** `&quot;` to `"` so you can safely write: `class="color = red"` even if the attribute list itself was HTML-escaped in surrounding content.  
- Inline code and code blocks **escape** HTML characters before emitting.  
- The inline renderer preserves backslash escapes for ``\` `` and `\$` to allow literal backticks/dollars.

---

## 6) End‑to‑end examples

### 6.1 Inline styles (all forms)

```dcz
# Styles demo

Shorthand: @(class="underline"){underlined}.

Explicit: @style(class="font-weight = 600") boldish @end text.

Alias:
@styledef {
  note = "rounded bg-yellow-50 px-2 py-1 text-yellow-900"
}
@(name="note"){Alias styles are handy.}

Heuristic:
The @style(class="color: red") red @end warning.
```

Expected HTML excerpts:

```html
<p>Shorthand: <span class="underline">underlined</span>.</p>
<p>Explicit: <span style="font-weight = 600"> boldish </span> text.</p>
<p><span class="rounded bg-yellow-50 px-2 py-1 text-yellow-900">Alias styles are handy.</span></p>
<p>The <span style="color: red"> red </span> warning.</p>
```

### 6.2 KaTeX + Code + Links

```dcz
Einstein: $E = mc^2$. See [Zig](https://ziglang.org) and `inline` code.
```

### 6.3 WASM + Canvas

```dcz
# Interactive

@wasm(name="game", src="/wasm/game.wasm", mount="#game") {
  <canvas id="game" width="800" height="450"></canvas>
}
```

### 6.4 CSS + Import

```dcz
@import(href="/third_party/katex/0.16.22/dist/katex.min.css")

@css {
  .callout { border-left: 4px solid #0ea5e9; padding: .75rem 1rem; }
}

@(class="callout"){This is a callout.}
```

---

## 7) HTML export mapping (author expectations)

Docz’s HTML exporter currently follows these mappings:

| AST Node   | HTML (representative)                                          |
|------------|-----------------------------------------------------------------|
| Document   | wrapper assembled by exporter (`<!DOCTYPE html> …`)            |
| Meta       | used to populate `<title>`, `<meta>` in `<head>`                |
| Heading    | `<h{level}>{text}</h{level}>`                                   |
| Content    | `<p>{inline-rendered}</p>`                                      |
| CodeBlock  | `<pre><code>{escaped}</code></pre>`                             |
| Math       | `<div class="math">{verbatim math delimiters}</div>`            |
| Media      | `<img src="…">` or appropriate element for type                 |
| Css        | `<style>…</style>` or extracted (depending on build flags)      |
| Import     | `<link>` / `<script>` tags (or pipelined)                       |
| StyleDef   | affects alias map only (no direct HTML)                         |
| Style      | rendered container `<div class="…">…</div>` if used as block    |

**No implicit sections.** If you want sectioning, create headings or write a custom `@section(...) { … }` directive in your pipeline.

---

## 8) Authoring guidelines (a11y, performance, portability)

- **A11y**: Use proper headings order; add `alt` text for `@img`; avoid color-only cues; keep contrast.  
- **Math**: Prefer LaTeX that KaTeX supports (nearly all common macros); keep inline expressions short.  
- **WASM**: Provide graceful fallbacks if a browser cannot run WASM/WebGPU; consider a “view-only” mode.  
- **Tailwind**: Use utility classes judiciously; prefer aliases (`@styledef`) for repeated patterns.  
- **Portability**: Avoid absolute asset paths for portable docs; use relative paths or a configurable asset root.  
- **Security**: Avoid embedding dangerous inline JS. Keep `@wasm` loader under your control.

---

## 9) Grammar sketch (informal EBNF)

> This sketch is intentionally permissive; your parser may be slightly more restrictive around whitespace and newlines.

```
document    := { block | content_line } ;

block       := heading
            | code_block
            | math_block
            | directive_block
            | meta_line ;

heading     := h1 | h2 | h3 | h4 | h5 | h6 ;
h1..h6      := {1..6} * '#' , ' ' , text , newline ;

content_line:= text_line , newline ;   // accumulated into Content paragraphs

code_block  := "```" , [lang] , newline , { any_line } , "```" , newline ;

math_block  := "$$" , newline , { any_line } , "$$" , newline ;

directive_block
            := '@' , ident , '(' , attr_list , ')' ,
               ( '{' , directive_body , '}' 
               | content_until("@end") ) ;

attr_list   := { attr , [ (',' | space) ] } ;
attr        := ident , ( '=' | ':' ) , quoted_or_plain ;

inline      := code_span | link | style_inline | raw_text ;

code_span   := '`' , { any_char_but_unescaped_backtick } , '`' ;

link        := '[' , { not ']' } , ']' , '(' , { not ')' } , ')' ;

style_inline:= '@' '(' , attr_list , ')' , '{' , body , '}' ;

meta_line   := '@meta(' , attr_list , ')' , newline ;
```

---

## 10) FAQ (sharp edges & guarantees)

**Q: Does free text create `<section>` elements?**  
A: No. Free text becomes **Content** → `<p>…</p>`. Use headings if you want document structure; build a `@section` directive otherwise.

**Q: Do I need to escape `$` for math?**  
A: No; the inline renderer preserves `$...$`. Escape as `\$` if you intend a literal dollar in contexts where it would look like math.

**Q: How are quotes handled in attribute lists?**  
A: `&quot;` is decoded to `"` during attribute parsing so you can safely embed quotes inside values. Text content outside attributes is not decoded automatically.

**Q: Tailwind vs CSS?**  
A: If a `class` contains `:`, `=` or `;`, it’s treated as CSS and emitted into `style=…`. Otherwise it’s left as class tokens for Tailwind/regular CSS.

**Q: Can inline style attributes include actions?**  
A: Yes—`on-click`, `on-hover`, `on-focus` are exported as `data-on-*` so client code can attach behavior.

**Q: How do I include third‑party CSS/JS?**  
A: `@import(href="...")` (the pipeline will vendor/lock expected versions when configured).

**Q: Are lists/tables supported natively?**  
A: Core keeps paragraphs simple. You can: (a) use your theme to style `-`/`*` prefixed lines, (b) embed raw HTML (`<ul>…</ul>`, `<table>…</table>`), or (c) extend the parser with a plugin.

---

## 11) Conformance checklist for generators (LLMs, scripts)

When generating `.dcz`:

- Prefer short, clear headings; keep one top‑level `#` title.  
- Keep paragraphs short; one idea per paragraph.  
- Use inline styles via `@(…) { … }` for small emphasis; use aliases for repeated styles.  
- Embed math with `$…$` (inline) or `$$ … $$` (block).  
- Use `@img` with `alt`.  
- Keep external imports explicit; avoid relying on global CDN assumptions.  
- If Tailwind is expected, stick to known classes; avoid arbitrary CSS in `class` unless intentional.  
- Escape backticks inside code as ``\` `` if needed.  
- Avoid introducing unclosed `@style` blocks; prefer shorthand if body is small.  
- Validate with Docz tests (unit/integration/e2e).

---

## 12) Compatibility & versioning

- This spec targets the Docz behavior reflected by the current tests (inline renderer, exporter) you’ve shown.  
- Backwards compatibility: future versions may add directives; existing constructs remain stable.  
- If your AST evolves (e.g., you add `Section` nodes), update the “HTML export mapping” table and grammar sketch.

---

## 13) Appendix — Full examples

### 13.1 Complete page

```dcz
@meta(key="title", value="DCZ Spec — Demo")
@meta(key="lang",  value="en")

# DCZ Demonstration

Welcome to **Docz**. Inline code like `let x = 1;` is escaped.  
Links like [Zig](https://ziglang.org) work. Math inline: $a^2+b^2=c^2$.

## Styles

@styledef {
  note   = "rounded bg-yellow-50 px-2 py-1 text-yellow-900"
  danger = "bg-red-50 text-red-700 px-1 rounded"
}

@(name="note"){This is a note.}  
@(class="text-green-600 font-semibold"){Success}  
The @style(class="color: red") red @end warning.

## Code

```zig
const std = @import("std");
pub fn main() !void {
    std.debug.print("hi\n", .{});
}
```

## Math block

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

## Image

@img(src="/img/logo.png", alt="Logo", class="h-12 mx-auto")

## CSS + Import

@import(href="/third_party/katex/0.16.22/dist/katex.min.css")

@css {
  .callout { border-left: 4px solid #0ea5e9; padding: .75rem 1rem; }
}

@(class="callout"){This is a callout.}

## WASM

@wasm(name="sim",
      src="/wasm/sim.wasm",
      mount="#m1",
      memory="64MiB") {
  <canvas id="m1" width="720" height="405"></canvas>
}
```

---

**End of GOLD spec.**
