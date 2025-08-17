# 📘 Docz File Specification (`.dcz`) — Canonical Reference (v1.2)

**Status:** Stable (authoring + implementation guide)  
**Audience:** Authors, parser/renderer/plugin implementers, test writers  
**Goal:** Be the *north star* for writing, parsing, rendering, and debugging `.dcz` files. No ambiguity.

> This spec defines: tokens, grammar, directives, shorthand syntax (Markdown‑like), defaults, aliasing, escaping, style mapping, and error semantics. It is intentionally verbose to remove guesswork.

---

## 0. Design Principles

- **Human-first authoring** with **machine-precise parsing**.  
- **One format** for prose, math, code, data, and structure.  
- **Shorthand** for speed (Markdown‑style) ⇄ **Directives** for precision (`@... @end`).  
- **Deterministic AST**: the same input always yields the same AST.  
- **Forward compatibility**: unknown directives are preserved as nodes.  
- **Styling is separate** (e.g., `assets/css/docz.core.css` defines look, not meaning).

---

## 1. File Encoding & Normalization

- **Encoding:** UTF‑8 text.  
- **Line endings:** `\n` (normalize `\r\n` to `\n` in tokenization).  
- **Tabs:** treated as 4 spaces *for indentation heuristics only*.  
- **Trailing spaces:** ignored unless in preformatted blocks (`@code`, `@data`, raw fences).  
- **BOM:** discouraged; if present, ignored.

---

## 2. High‑Level Structure

A `.dcz` file is a sequence of **blocks** and **inline spans**.

- **Blocks:** paragraphs, lists, tables, headings, quotes, code, math, images, plugins, etc.  
  - **Directive blocks:** start with `@name(...)` and end with `@end`.  
  - **Shorthand blocks:** Markdown‑like forms (`#`, `-`, `1.`, `>`, ``` ``` ``` fences, etc.).
- **Inline spans:** emphasis, strong, underline, strike, code, math, links, escapes.

Renderers MUST convert **stray text** (text not inside another block) into a **Paragraph** block by default. Equivalent explicit forms exist (`@paragraph`, alias `@p`).

---

## 3. Tokens & Lexical Rules

**Token types (minimum):**
- `DirectiveStart(name)` — e.g., `@heading`, `@code`, `@math`, `@paragraph`, etc.
- `ParamOpen` `(`, `ParamClose` `)` — parameter list delimiters.
- `ParameterKey`, `ParameterValue`, `Comma`, `Equals`.
- `Content` — raw text payload for the block.
- `BlockEnd` — the literal `@end` (must close the **current** open directive).
- `FenceStart(language?)`, `FenceEnd` — for ``` ``` style shorthand code blocks.
- `LinePrefix` markers for shorthand blocks (`#`, `-`, `1.`, `>`, etc.).
- `InlineDelim` — `$`, `$$`, `` ` ``, `**`, `*`, `~~`, `++`.
- `Escape` — `@@` → literal `@`.
- `CommentOpen` `<!--`, `CommentClose` `-->` (HTML‑style comments).

**Escaping:**
- `@@` → literal `@` anywhere.  
- Inside `@code`, `@data`, and fenced code blocks, everything is raw until their close; `@@` is not required inside these raw blocks.  
- Inside `@math` blocks, treat content as math (LaTeX); only `@end` ends the block.

**Parameter value grammar (in parens):**
- Strings may be quoted: `key="value with spaces and , commas"`  
- Barewords: `key=value` where `value` matches `[A-Za-z0-9_\-./:]+`  
- Numbers: `key=123`, `key=3.14`  
- Booleans: `key=true|false`  
- Flags: presence implies `true` (e.g., `@image(inline)` → `{inline:true}`).  
- Commas separate pairs: `key1=..., key2="...", flag`

---

## 4. Blocks — Canonical Directive Forms (authoritative)

> All directive blocks MUST end with an explicit `@end`, even if on one line.

### 4.1 `@heading`
```dcz
@heading(level=1) Title @end
@heading(level=2) Subtitle @end
```
- **Params:** `level=1..6` (required unless using alias `@h1..@h6`, see §6)  
- **Content:** the heading text (single line preferred; multiline allowed).  
- **HTML:** `<h1>…</h1>` .. `<h6>…</h6>`

### 4.2 `@paragraph` (alias: `@p`)
```dcz
@paragraph
Freeform prose. If you omit @paragraph/@p entirely, stray text becomes a paragraph.
@end
```
- **HTML:** `<p>…</p>`

### 4.3 `@code`
```dcz
@code(language="zig", linenos=false)
const x = 42;
@end
```
- **Params:** `language` (optional), `linenos` (optional bool)  
- **Content:** raw, preserved verbatim.  
- **HTML:** `<pre><code class="language-zig">…</code></pre>`

### 4.4 `@math`
```dcz
@math
E = mc^2
@end
```
- **Content:** LaTeX math (KaTeX).  
- **HTML:** block math wrapper; renderer executes KaTeX.

### 4.5 `@list`
```dcz
@list(type="bullet", tight=false)
- Milk
- Eggs
  - Free-range
- Bread
@end
```
- **Params:** `type="bullet"|"ordered"|"task"`, `tight` (bool)  
- **Content:** composed of **shorthand items** (see §5.3); renderer parses into a List block.  
- **HTML:** `<ul> / <ol> / <ul class="task-list">` etc.

### 4.6 `@table`
```dcz
@table(format="markdown")  # default format is "markdown"
| Name | Value |
|------|-------|
| Foo  | 42    |
| Bar  | 99    |
@end
```
- **Params:** `format="markdown"|"csv"`  
- **HTML:** `<table>…</table>` (align based on dashes/colons if provided).

### 4.7 `@image`
```dcz
@image(src="figs/plot.png", alt="A Plot", width="480", height="auto", inline)
@end
```
- **Params:** `src` (required), `alt` (optional), `width`/`height`, `inline` flag.  
- **HTML:** `<img ...>` (wrapped in `<figure>` if `caption` is provided; see next).

### 4.8 `@figure` (optional but recommended)
```dcz
@figure
  @image(src="figs/plot.png", alt="A Plot") @end
  @caption An informative caption. @end
@end
```
- **HTML:** `<figure> <img> <figcaption>…</figcaption> </figure>`

### 4.9 `@link`
```dcz
@link(href="https://ziglang.org") Zig Homepage @end
```
- **HTML:** `<a href="…">…</a>`

### 4.10 `@quote`
```dcz
@quote
> Nested shorthand is allowed:
> “Mathematics is the language…” — Galileo
@end
```
- **HTML:** `<blockquote>…</blockquote>`

### 4.11 `@style`
```dcz
@style
/* CSS or Tailwind-friendly HTML snippets */
p { line-height: 1.7; }
@end
```
- **Security:** renderers MAY sandbox or strip disallowed rules.  
- **Source of truth for defaults:** `assets/css/docz.core.css`

### 4.12 `@meta`
```dcz
@meta
title = "Docz Spec"
author = "James"
date = "2025-08-16"
version = "1.2"
@end
```
- **Semantics:** renderer MAY consume for title blocks, TOC, PDF metadata, etc.

### 4.13 `@data`
```dcz
@data(format="csv")
x,y
1,2
3,4
@end
```
- **Params:** `format="csv"|"json"|"yaml"`  
- **Usage:** for charts, tables, or plugin inputs.

### 4.14 `@plugin`
```dcz
@plugin(name="diagram", type="mermaid", theme="default")
graph TD; A-->B; B-->C;
@end
```
- **Params:** `name` (required), others plugin-specific.  
- **Error policy:** If unknown, render a literal placeholder node but keep payload intact.

### 4.15 `@comment`
```dcz
@comment
This entire block is ignored by renderers (not emitted).
@end
```

### 4.16 `@hr` (self-closing)
```dcz
@hr
```
- **No `@end`**. Emits `<hr />`.

### 4.17 `@br` (self-closing)
```dcz
@br
```
- **No `@end`**. Emits `<br />`.

---

## 5. Shorthand Syntax (Markdown‑style)

Shorthand exists for speed. Shorthand MUST round‑trip to the same AST as their directive equivalents.

### 5.1 Headings
```
# H1 Title
## H2 Title
### H3 Title
#### H4 Title
##### H5 Title
###### H6 Title
```
**Mapping:** `#` → `@heading(level=N) … @end`

**Aliases (explicit):**
```
@h1 Title @end
@h2 Title @end
...
@h6 Title @end
```
(These are exact equivalents to `@heading(level=N)`.)

### 5.2 Paragraphs
- **Stray text** becomes a Paragraph block.  
- Explicit forms:
  - `@paragraph ... @end`
  - `@p ... @end`

### 5.3 Lists
**Bullets:**
```
- item A
* item B
+ item C
```
**Ordered:**
```
1. first
2. second
```
**Task list (checkboxes):**
```
- [ ] open task
- [x] done task
```
**Mapping:** these lines inside a list region → `@list(type=...) ... @end` with nested ListItems in AST.  
**Nesting:** indent by 2+ spaces or a tab to nest.

### 5.4 Blockquotes
```
> quoted line
>> nested quote
```
**Mapping:** one or more `>` prefixes → nested `@quote` blocks.

### 5.5 Code Fences
````
```zig
const x = 42;
```
````
- Language after the opening fence is optional.  
- **Mapping:** fenced block → `@code(language="zig") ... @end`

### 5.6 Inline Spans
- **Bold:** `**strong**` or `__strong__` → `<strong>`  
- *Italic:* `*emphasis*` or `_emphasis_` → `<em>`  
- ++Underline++: `++underline++` → `<u>` (Docz extension; not GitHub MD)  
- ~~Strike~~: `~~strike~~` → `<del>`  
- `Inline code`: `` `code` `` → `<code>`  
- Inline math: `$a^2 + b^2$` → math span (KaTeX inline)  
- Links: `[label](https://example.com "optional title")` → `<a>`  
- Images: `![alt](path "title")` → `@image(...)` node

> **Underline note:** We intentionally reserve `++text++` for underline to avoid conflicts with `__text__` (bold) commonmark variations.

### 5.7 Horizontal Rule
```
---
```
or
```
***
```
**Mapping:** → `@hr`

### 5.8 Line Break
Two trailing spaces at EOL, or explicit `@br`.

### 5.9 HTML Comments
```
<!-- this is a comment -->
```
- **Mapping:** HTML comment tokens become `Comment` nodes that renderers MUST drop by default (like `@comment`), unless a renderer is in “preserve comments” mode.

---

## 6. Directive Aliases & Abbreviations

- `@p` → `@paragraph`
- `@h1`..`@h6` → `@heading(level=1..6)`
- Potential future short forms (informative): `@img` → `@image`, `@q` → `@quote`

Aliases MUST be treated as **exact** equivalents (same AST nodes/params).

---

## 7. Which Directives Require `@end`? (and why)

**Require `@end`** (block content must be delimited):
- `@heading`, `@paragraph`/`@p`, `@code`, `@math`, `@list`, `@table`, `@image`, `@figure`, `@link`, `@quote`, `@style`, `@meta`, `@data`, `@plugin`, `@comment`, `@caption` (subcomponent)

**Do NOT require `@end`** (self-closing; no content region):
- `@hr`, `@br`

**Rationale:**  
- Blocks that **contain content or children** must be explicitly closed to avoid mis-nesting and to keep the tokenizer deterministic.  
- Self-closing semantic atoms (`hr`, `br`) need no body, so no `@end`.

---

## 8. HTML/CSS Mapping (Styling vs Semantics)

- Semantics originate from directives/shorthand.  
- Visual defaults are defined in `assets/css/docz.core.css` (canonical default theme).  
- Authors SHOULD NOT rely on visual quirks; rely on **semantic blocks**.  
- Typical mappings:
  - Paragraph → `<p>`
  - Headings → `<h1>`..`<h6>`
  - List → `<ul>`/`<ol>`/`<ul class="task-list">`
  - Quote → `<blockquote>`
  - Code → `<pre><code class="language-…">`
  - Math → KaTeX-rendered `<span class="katex">` (inline) or block wrappers
  - Images → `<img>` (possibly inside `<figure>…<figcaption>…</figcaption></figure>`)

---

## 9. Math Rules (KaTeX)

- Inline: `$ … $` should not cross line breaks.  
- Block: `@math … @end` or `$$ … $$` on its own lines (renderer may convert to block).  
- Escaping `$`: `\$` inside non-math contexts.  
- Inside `@math`, the only terminator is `@end` on a new line.

---

## 10. Links, URLs, and Autolink

- Shorthand: `[label](href "title")`  
- Bare URLs MAY autolink (renderer option).  
- `@link(href="...") Label @end` is the explicit directive form (preferred for AST purity).

---

## 11. Images & Paths

- Shorthand: `![alt](path "title")`  
- Explicit: `@image(src="path", alt="…", width="…", height="…") @end`  
- Paths resolve **relative to the `.dcz` file** unless absolute or protocol (`http(s)://`, `data:`)  
- Renderer MAY allow `/third_party/...` static roots (e.g., KaTeX assets).

---

## 12. Tables

**Markdown style:**
```
| Name | Value |
|:-----|-----:|
| Foo  |   42 |
```
- Colons indicate alignment (`left`, `right`, `center`).  
- Empty leading/trailing pipes are optional.

**CSV style:**
```
a,b,c
1,2,3
```
- Use `@table(format="csv") … @end` to disambiguate.  
- Quoted CSV fields MUST be supported.

---

## 13. Error Handling & Diagnostics

Parsers MUST detect and report:
- Unclosed blocks (missing `@end`).  
- Mis-nested blocks (e.g., closing a parent while child is open).  
- Unknown parameters or invalid values (warn, do not hard-fail).  
- Fence mismatch (unclosed ``` blocks).  
- Ambiguous inline delimiters (e.g., unmatched `**`/`*`/`++`/`~~`): fallback is to treat as plain text and emit a warning.

**Unknown directives:** Preserve as `UnknownDirective(name, params, content)` nodes; renderers should emit a neutral placeholder with the raw content or skip with a warning (configurable).

**Leniency toggles:** Implementations SHOULD provide `strict` vs `lenient` modes for CI vs authoring.

---

## 14. Whitespace, Indentation, and Trimming

- Surrounding blank lines are NOT significant except to delimit blocks.  
- Leading/trailing whitespace inside `@code`, `@data` is preserved verbatim.  
- Other blocks trim leading/trailing blank lines within content.  
- Indentation defines nesting for list shorthand; for other blocks, indentation is preserved only if meaningful (e.g., code).

---

## 15. Security Considerations

- `@style` and plugin content may introduce unsafe CSS/JS. Renderers SHOULD sandbox or sanitize.  
- Remote images/links can leak information; allow offline/whitelisting modes.  
- Never auto-execute code in `@code` or `@data` unless an explicit execution sandbox is enabled by the host application.

---

## 16. Conformance Levels

- **Authoring-conformant:** Uses any allowed shorthand or directives; renders correctly.  
- **AST‑conformant:** Produces the canonical AST shape described here.  
- **Renderer‑conformant:** Maps canonical AST to HTML/LaTeX/Markdown predictably.  
- **Plugin‑conformant:** Registers under a unique name; declares params; pure transform from AST input to output subtree.

---

## 17. Canonical AST Shapes (Illustrative)

**Heading:**
```json
{
  "type": "Heading",
  "level": 2,
  "children": [{ "type": "Text", "value": "Subtitle" }]
}
```

**Paragraph with spans:**
```json
{
  "type": "Paragraph",
  "children": [
    { "type": "Text", "value": "Hello " },
    { "type": "Strong", "children": [{ "type": "Text", "value": "world" }] },
    { "type": "Text", "value": " and " },
    { "type": "Underline", "children": [{ "type": "Text", "value": "friends" }] }
  ]
}
```

**Task list:**
```json
{
  "type": "List",
  "ordered": false,
  "task": true,
  "children": [
    { "type": "ListItem", "checked": false, "children": [...] },
    { "type": "ListItem", "checked": true, "children": [...] }
  ]
}
```

**Code fence:**
```json
{
  "type": "Code",
  "language": "zig",
  "value": "const x = 42;\n"
}
```

---

## 18. Shorthand ⇄ Directive Mapping Table (Authoritative)

| Shorthand | Directive Equivalent | Notes |
|---|---|---|
| `# …` → `###### …` | `@heading(level=n) … @end` | n = count of `#` |
| stray text | `@paragraph … @end` | or alias `@p` |
| `- item`, `* item`, `+ item` | `@list(type="bullet") … @end` | nesting by indentation |
| `1. item` | `@list(type="ordered") … @end` | numbering captured |
| `- [ ] item` / `- [x] item` | `@list(type="task") … @end` | `checked` per item |
| `> quote` | `@quote … @end` | nested `>` → nested quotes |
| ``` ``` (with lang) | `@code(language="...") … @end` | fences map to code |
| `![alt](src "title")` | `@image(src="src", alt="alt") @end` | title optional |
| `[label](href)` | `@link(href="href") label @end` | title optional |
| `**strong**`, `__strong__` | `<strong>` | inline span |
| `*em*`, `_em_` | `<em>` | inline span |
| `++u++` | `<u>` | inline span (Docz extension) |
| `~~del~~` | `<del>` | inline span |
| `` `code` `` | `<code>` | inline span |
| `$…$` | inline math | KaTeX inline |
| `---` / `***` | `@hr` | horizontal rule |
| two trailing spaces EOL | `@br` | line break |
| `<!-- … -->` | comment node | dropped by default |

---

## 19. Comments

Two systems exist and are equivalent in effect (ignored by default):

1) **Block comment directive:**
```dcz
@comment
This won’t render.
@end
```

2) **HTML comment shorthand:**
```
<!-- This won’t render either. -->
```

Renderers MUST provide a debug mode to **preserve** comments for inspection.

---

## 20. Examples & Edge Cases (Test‑Ready)

### 20.1 Mixed Shorthand + Directives
```dcz
@meta
title = "Mixed Example"
@end

# Intro
This is **bold**, *italic*, ++underlined++, and ~~struck~~.

- [ ] todo one
- [x] done two
  1. nested ordered
  2. still ordered

```zig
const x = 42;
```

@image(src="figs/a.png", alt="A") @end

> A quote
>> Nested quote

@math
\int_0^1 x^2 dx = \frac{1}{3}
@end
```

### 20.2 Escapes & Literals
```dcz
Use @@heading to write "@heading" literally.
Inside code blocks, @@ is not required:
@code
@not_a_directive
@end
```

### 20.3 Tables
```dcz
@table
| Name | Count |
|:-----|------:|
| Foo  |     7 |
| Bar  |    13 |
@end
```

### 20.4 Strictness
- Missing `@end` → error with line number and open‑block stack.  
- Unclosed fences → error with line number.  
- Unknown directive → warning (preserve as UnknownDirective).

---

## 21. Defaults & Core CSS (`assets/css/docz.core.css`)

- **Margins, max-width, typography**: managed by `docz.core.css`.  
- **Inline code thickness** and spacing are theme choices.  
- **Responsiveness**: core CSS provides sane defaults; themes can override.  
- **Accessibility**: ensure sufficient contrast and semantic tags.

---

## 22. Versioning & Metadata

- `@meta.version` is advisory for documents.  
- Parser/renderer SHOULD embed their own version in output metadata for traceability.  
- Future spec changes will be backwards compatible or guarded by `@meta` flags.

---

## 23. Frequently Asked Implementer Questions (FAQ)

**Q:** Why force `@end` for headings if they’re one‑liners?  
**A:** Determinism. Uniform closure reduces edge cases, allows multiline headings, and enables consistent nesting rules.

**Q:** Why support both shorthand and directives?  
**A:** Authors write fast; tools need precision. We keep both and guarantee identical ASTs.

**Q:** Does Docz allow raw HTML?  
**A:** Discouraged. Prefer semantic directives. Renderers MAY allow a safe subset behind a flag.

**Q:** Underline isn’t in CommonMark—why `++u++`?  
**A:** To avoid Overloading `__` (bold) and maintain an unambiguous, parseable signal.

---

## 24. Minimal Grammar (EBNF‑like, illustrative)

```
document    := block* EOF ;

block       := directive_block
             | fenced_code
             | heading_shorthand
             | list_shorthand
             | quote_shorthand
             | hr_shorthand
             | html_comment
             | paragraph ;

directive_block
            := '@' IDENT params_opt content_opt '@end' ;

params_opt  := '(' param (',' param)* ')' | ε ;
param       := IDENT ('=' value)? ;
value       := QUOTED | NUMBER | BOOLEAN | BAREWORD ;

fenced_code := '```' IDENT? NEWLINE raw_until_fence '```' ;

heading_shorthand
            := HASH{1..6} SPAN+ NEWLINE ;

list_shorthand
            := (bullet_item | ordered_item | task_item)+ ;

quote_shorthand
            := '>' SPAN+ NEWLINE ;

paragraph   := inline_span+ (NEWLINE inline_span+)* ;

inline_span := bold | italic | underline | strike | code_inline | math_inline | link | text ;
bold        := ('**' text '**') | ('__' text '__') ;
italic      := ('*' text '*') | ('_' text '_') ;
underline   := '++' text '++' ;
strike      := '~~' text '~~' ;
code_inline := '`' not_backtick '`' ;
math_inline := '$' not_dollar '$' ;
link        := '[' text ']' '(' url (SP title)? ')' ;
```

---

## 25. Compliance Checklist (for CI)

- [ ] Shorthand ↔ directive round‑trips to identical AST.  
- [ ] Enforces `@end` for all non‑self‑closing directives.  
- [ ] Preserves raw content in `@code`, `@data`, fenced blocks.  
- [ ] KaTeX inline/block rendered and escaped correctly.  
- [ ] Lists (ordered/bullet/task) nest predictably via indentation.  
- [ ] Tables (markdown + csv) parse consistently (alignment honored).  
- [ ] Comments (`@comment`, `<!-- -->`) dropped by default; preservable in debug mode.  
- [ ] Unknown directives preserved (warning).  
- [ ] All errors provide line/column with open‑block context.  
- [ ] `assets/css/docz.core.css` default theme renders clean, readable output.

---

**Version:** 1.2 (August 16, 2025)  
**Maintainer:** Docz Core
