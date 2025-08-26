
# Docz File Specification (v0.2-draft)

> Status: **Working draft** — aligned with the current tokenizer, parser, and HTML exporter in this repository.  
> Scope: Documents the **baseline** that exists today and the **near‑term** additions we agreed to. Where something is “planned / not yet implemented”, it’s called out explicitly.

---

## 1. Design Goals

- **Human-first, AI-friendly.** Files should be easy to read and write by humans, while being unambiguous for parsers and LLMs.  
- **Markdown‑inspired ergonomics.** Common authoring patterns (headings, paragraphs, code, lists) feel familiar.  
- **Full HTML/CSS power.** You can reach the same expressiveness as HTML + CSS without leaving `.dcz`.  
- **Single-pass parsing.** A predictable tokenizer+parser that does not silently rewrite user input.  
- **Zero‑node runtime.** Compiles to self‑contained HTML (plus optional vendored assets).  
- **Extensibility.** New directives can be added without breaking old files.

Non‑goals (for now):

- A complete Markdown superset. The goal is **clarity over cleverness**.  
- A browser‑framework runtime (e.g., Svelte/React component system). Hooks and actions are out of scope for v0.2.

---

## 2. File Format & Encoding

- **UTF‑8**. Optional UTF‑8 BOM is tolerated and ignored.  
- **Line endings:** `\n` or `\r\n`.  
- **Comments:** Lines beginning with `#:` are ignored to the end of line.  
- **Whitespace:** Insignificant between top‑level constructs; significant inside fenced blocks.

---

## 3. Tokenization Rules

Token kinds:
- `Directive` — a `@` at start of a (possibly indented) line, followed by an identifier made of `[A‑Za‑z0‑9_-]+`; e.g. `@code`, `@style-def`.  
- `ParameterKey` / `ParameterValue` — inside `(...)` immediately after a directive. Keys match `[A‑Za‑z0‑9_-]+`. Values may be quoted (`"..."`) or unquoted (up to whitespace, `,` or `)`).  
- `Content` — everything else (lines and text not captured as directives or params).  
- `BlockEnd` — a line that, when trimmed of spaces/tabs/CR, equals `@end`. This may also appear inline **at end of line** (e.g., `... @end`) and is still recognized.

Special cases and escapes:

- `@@` at any position means **emit a literal `@`** followed by the next non‑whitespace “word” in the same token (e.g. `@@support@example.com → "@support@example.com"`).  
- **Fenced directives** capture *raw* content until a closing `@end` (either on its own trimmed line **or** at the end of a line). Current fenced set: **`@code`, `@math`, `@style`, `@css`**.  
- Inside fenced blocks the tokenizer does not try to parse nested directives, except that it still looks for the **terminating** `@end` as described above.
- A directive is considered **start‑of‑line (SOL)** if it’s at the beginning of a line or is preceded only by spaces/tabs.  
- Stray `@end` outside a fence — when its *trimmed* line is `@end` — still results in a `BlockEnd` token. Consumers decide how to treat it.

Error‑hardening:

- Parameter lists that never close `)` do **not** hang; the tokenizer advances safely.  
- An infinite‑loop guard returns `error.TokenizerStuck` if the input does not make progress after many iterations.

---

## 4. Core Directives (v0.2)

### 4.1 `@meta(...)` — Document metadata

- **Form:** `@meta(title:"...", author:"...", default_css:"...", debug_css:"true")`  
- **Where:** Anywhere at top level. Multiple are allowed; **last write wins** for duplicate keys.  
- **HTML export:** `title` → `<title>…</title>` (first only); all other keys → `<meta name="k" content="v">`.  
- Recognized convenience keys:
  - `default_css`: emits `<link rel="stylesheet" href="…">` in `<head>`  
  - `debug_css`: if `"true"`/`"1"`, shows a small debug banner in `<body>` with details of CSS gathered from the document.

### 4.2 `@import(href:"/...")` — Stylesheet link

- **Form:** `@import(href:"/styles/site.css")`  
- **HTML export:** `<link rel="stylesheet" href="...">` in `<head>`.  
- **Note:** Only `href` is used today; more attributes may be added later.

### 4.3 `@code(...) … @end` — Fenced code

- **Params:** `lang:"bash"` (optional).  
- **Body:** Treated as raw text; HTML‑escaped on export.  
- **HTML export:** `<pre><code class="language-<lang>">…</code></pre>` (no class if `lang` missing).

### 4.4 `@math … @end` — Display math

- **Body:** Raw math markup (KaTeX/MathJax compatible).  
- **HTML export:** `<div class="math">…</div>`; live preview injects the KaTeX auto‑render snippets when vendored assets are present.

### 4.5 `@style(mode:"global") … @end` — Global style definitions (aliases)

- **Aliased by:** `@css … @end` (shorthand).  
- **Body syntax:** one alias per line:
  ```
  heading-1: h1-xl h1-weight
  body-text: prose max-w-none
  ```
- **Effect:** Populates a **style alias map**: name → class list. **Last write wins** across multiple blocks.  
- **HTML export:** No direct output in `<body>`. Aliases are used by inline `@style` (below).

### 4.6 Inline `@style(...) … @end` — local styling inside a paragraph

- **Where:** Inline, inside a paragraph’s text (i.e., `Content` tokens).  
- **Params (choose one):**
  - `style:"color:red; font-weight:600"` → inline CSS  
  - `class:"btn btn-primary"` → class list (space‑separated)  
  - `name:"heading-1"` → look up classes from the alias map built by `@style(mode:"global")`/`@css`  
- **Precedence:** `style` > `class` > `name`.  
- **HTML export:** Rewritten to a `<span …>…</span>` with either a `style` or `class` attribute accordingly.  
- **Malformed fallback:** If the directive cannot be parsed, the exporter **leaves the original text** unchanged (no silent loss).

> **Note on `class` vs `classes`:** Docz uses **`class`** consistently (singular) to avoid ambiguity. Multiple classes are separated by spaces.

---

## 5. Inline Shorthand (v0.2)

Inline shorthand is **optional** and never required. When present, the CLI can normalize it with `docz convert --explicit` (see §12).

### 5.1 Primary shorthand: `@{ … }text@end`

- **Examples:**
  - `Make @{ class:"badge warn" }this@end pop.`
  - `Make @{ style:"color:red; text-decoration:underline" }this@end pop.`
  - `Make @{ name:"heading-1" }this@end pop.`
- **Semantics:** Exactly equivalent to inline `@style(...) … @end`.
- **Why `@{`?** Low collision risk in prose and code blocks, and consistent with the `@` directive family.

> **Note:** The older experimental `. { … }` (“dot‑brace”) shorthand is **discouraged** because it collides with common code/text. It is not part of this v0.2 spec.

---

## 6. Structural Markdown‑inspired Syntax (baseline)

Docz accepts a small, explicit subset of Markdown‑like patterns in **Content** nodes:

- Lines starting with `#`, `##`, `###` → rendered as `<h1>`, `<h2>`, `<h3>` respectively.  
- Blank lines separate paragraphs.  
- Inline emphasis inside paragraphs (`**bold**`, `*italic*`, `` `code` ``) is supported in the **fallback renderer**; the canonical AST currently treats paragraphs as raw `Content` and lets exporters post‑process.  
- Links using `[label](href)` in Content are passed through by the fallback renderer; a richer link directive may be added later for structured links.

> This section documents current behavior, not a normative commit to a full Markdown grammar. The guiding principle is *predictability*.

---

## 7. AST Model (current)

Node types used by the HTML exporter:

- `Document` (root)
- `Meta` — key/value map
- `Import` — `href`
- `Css` — accumulated from fenced `@style(mode:"global")` or `@css` if an implementation chooses to inline CSS rather than link files
- `StyleDef` — raw alias block (parsed into the alias map)
- `Style` — inline style span (`style` / `class` / `name`) with `content`
- `Heading` — attributes: `level`; `content` holds the plain heading text
- `Content` — paragraph text (may contain inline `@style(...) … @end` which is rewritten by the exporter)
- `CodeBlock` — attributes: `lang`; `content` is raw code
- `Math` — `content` is raw math
- `Media` — attributes: `src` (exported as `<img src>` today; future expansion may support `alt`, `width`, `height`)

Allocation/ownership rules (for implementers):

- Node structs own their attribute keys/values and `content` by convention. 
- Exporters must **not** mutate provided buffers; they allocate new HTML as needed.

---

## 8. HTML Export (normative for v0.2)

### 8.1 `<head>` emission

- Collect all `Meta` → `<title>`(first) and `<meta name="…" content="…">`.  
- Emit `Import(href)` as `<link rel="stylesheet" href="…">`.  
- Optionally emit `<link rel="stylesheet" href="{default_css}">` from `@meta`.  
- If the pipeline chooses to inline CSS, merge all `Css` nodes into a single `<style>…</style>` block.  
- Live preview may inject KaTeX assets and a hot‑reload script after `<head>` is assembled (implementation detail, not file‑level).

### 8.2 `<body>` emission

- `Heading(level)` → `<h{level}>{text}</h{level}>` (level ∈ {1,2,3}).  
- `Content` → `<p>…</p>`, after applying **inline rewrite** (see §8.3).  
- `CodeBlock` → `<pre><code class="language-<lang>">…</code></pre>` (HTML‑escaped).  
- `Math` → `<div class="math">…</div>`.  
- `Style` → `<span class="…">…</span>` or `<span style="…">…</span>` based on resolved attributes.  
- `Media` → `<img src="…">` (current minimal support).  
- `StyleDef`, `Import`, `Css`, `Meta` → no direct body output.

### 8.3 Inline rewrite (paragraph‑local)

When a paragraph’s text contains inline `@style(...) … @end`, the exporter **rewrites** each occurrence to a `<span …>…</span>` with the following steps:

1. **Find** `@style(`, parse the parenthesized attribute slice `key[:]"value"[,…]` (quoted or unquoted values).  
2. **Find body**: optional whitespace after `)` then capture until the next `@end`.  
3. **Resolve attributes**:
   - If `style` present → use `style="…"`.  
   - Else if `class` present → use `class="…"`.  
   - Else if `name` present and found in alias map → `class="resolved classes"`.  
   - Else → treat as malformed; emit the original literal text unchanged.  
4. **Escape attribute values** for HTML attributes. The **inner body** is inserted verbatim (the exporter escapes the paragraph text as a whole beforehand if needed).  
5. **Continue** scanning after the consumed `@end`.

Robustness:

- If any part is missing (no closing `)`, no `@end`), drop back to **literal** output; do not crash or hang.  
- Nested inline `@style` inside the inner body is not supported in this version; the first well‑formed closing `@end` terminates the span.

---

## 9. Escaping Rules

- Inside paragraphs, the exporter escapes HTML special characters when emitting **raw text**.  
- The exporter’s attribute helpers must escape `&`, `<`, `>`, `"`, `'` in attribute values.  
- Code/math blocks are passed through with appropriate escaping, but **not** interpreted for directives.  
- Literal `@` is written as `@@…word` (see §3).

---

## 10. Tailwind & Theming

- The preview pipeline looks for the monorepo Tailwind build or the vendored theme and injects a link to `docz.tailwind.css` when available.  
- `@style(mode:"global")` defines aliases that are useful regardless of Tailwind usage. Aliases can reference Tailwind utility classes, custom theme classes, or plain CSS class names defined elsewhere.

---

## 11. Security Considerations

- Docz itself does **not** execute user code.  
- When emitting HTML, exporters must escape correctly to prevent XSS when viewing `.dcz` originating from untrusted sources.  
- Avoid injecting `<script>` from `.dcz` content directly; use vendored/known assets when needed (KaTeX).

---

## 12. CLI Normalization: `convert --explicit`

To aid AI tooling and diffs, Docz ships a normalization mode:

```
docz convert input.dcz --explicit > output.dcz
# or
docz convert input.dcz --to output.dcz --explicit
```

This pass rewrites shorthand into explicit directives while preserving semantics, for example:

- `@{ class:"warn" }text@end` → `@style(class:"warn") text @end`  
- Future shorthands, when added, will normalize similarly.

No reflow, no stylistic changes outside the shorthand; comments and spacing are preserved where possible.

---

## 13. Examples

### 13.1 Readable “landing” page

```
@meta(title:"Docz — A tiny, fast, ergonomic documentation engine", author:"Docz Authors")

@style(mode:"global")
heading-1: text-4xl font-bold
body-text: prose leading-7
@end

# Docz

**Docz** is a compact documentation engine and file format built for speed, clarity, and *developer ergonomics*.

## Quick Start

@code(lang:"bash")
zig build
zig build run -- run ./examples/hello.dcz
@end

Open the printed URL in your browser.

## Live Preview

The @{ class:"text-red-600 underline" }preview@end server exposes a small set of routes:

- `/view?path=docs/SPEC.dcz`
- `/render?path=docs/SPEC.dcz`
```

### 13.2 Styling inline content

```
Newton wrote @{ name:"body-text" }F = m a@end and highlighted @{ style:"text-decoration:underline" }a@end.
```

### 13.3 CSS aliasing with `@css`

```
@css
badge-warn: badge badge-warn
kbd: inline-block rounded border px-1 py-0.5 text-xs bg-neutral-100
@end

Press @{ name:"kbd" }Ctrl+C@end to abort.
```

---

## 14. Conformance

An implementation conforms to this spec if:

1. It implements the tokenization rules in §3 and recognizes the fenced set {`@code`, `@math`, `@style`, `@css`}.  
2. It builds an AST equivalent (or richer) to §7 from tokens without *changing* content.  
3. An HTML exporter that follows §8 (head/body/inline rewrite).  
4. It passes the normative test vectors in §15.

---

## 15. Normative Test Vectors (abbrev.)

Each case provides input and the *critical* fragment expected in HTML output.

### TV‑1 — Literal `@@`

Input: `Contact @@support@example.com`  
Expect: contains `<p>Contact @support@example.com</p>`

### TV‑2 — Inline `@style(class)`

Input: `The @style(class:"red") red @end warning.`  
Expect: contains `<p>The <span class="red">red</span> warning.</p>`

### TV‑3 — Inline `@style(name)`, aliasing

Input:
```
@style(mode:"global")
emph: text-red-600 underline
@end
Use @style(name:"emph") caution @end here.
```
Expect: `<span class="text-red-600 underline">caution</span>`

### TV‑4 — Inline `@style(style)`

Input: `A @style(style:"color:green") green @end idea.`  
Expect: `<span style="color:green">green</span>`

### TV‑5 — Fenced `@code`

Input:
```
@code(lang:"zig")
const std = @import("std");
@end
```
Expect: `<pre><code class="language-zig">const std = @import(&quot;std&quot;);</code></pre>`

### TV‑6 — `@math`

Input:
```
@math
E = mc^2
@end
```
Expect: `<div class="math">E = mc^2</div>`

### TV‑7 — `@end` only at EOL or trimmed line

Input: 
```
@code(lang:"txt")
abc @end
@end
```
Expect: Code block contains `abc` only, not `@end`.

### TV‑8 — Malformed inline (no `)`)

Input: `Bad @style(class:"x" inner @end text`  
Expect: The literal text is preserved; no crash or hang.

---

## 16. Versioning & Future Work

- v0.3 candidates:
  - Structured links: `@link(href:"…", text:"…") … @end` with nested content.  
  - Image/media directive with `alt`, `width`, `height`.  
  - Optional `@{ … }` shorthand enhancements and a canonical *inline‑style* grammar.  
  - Table/list blocks with clean directive forms.
- Any new directive must be added to the `TokenizerConfig.fenced_directives` (if it should capture raw content) and documented here.

---

## 17. Appendix A — Parameter Grammar (EBNF)

```
directive        = "@" ident [ "(" param_list ")" ] ;
ident            = ( ALNUM | "_" | "-" ) { ALNUM | "_" | "-" } ;
param_list       = param { "," param } ;
param            = key [ "=" value ] ;
key              = ident ;
value            = quoted | unquoted ;
quoted           = '"' { any_char - '"' } '"' ;
unquoted         = { any_char - whitespace - "," - ")" } ;

whitespace       = " " | "\t" | "\r" | "\n" ;
ALNUM            = "A"…"Z" | "a"…"z" | "0"…"9" ;
```

Notes:
- Escapes inside `quoted` are **not** interpreted in v0.2; exporters import the raw text.
- The tokenizer is line‑oriented and treats `@end` specially per §3.
