# 8. Styling & Interaction (`@style`)

`@style` is Docz’s **unified primitive** for attaching presentation (CSS) and behavior (actions) to content.
It works in both **Normal CSS mode** and **Tailwind-enabled mode** without changing your document syntax.

---

## 8.1 Goals

- **Uniformity:** one directive for CSS classes, inline styles, and interactive actions.
- **Portability:** compiles to clean, framework-free HTML + CSS; optional WASM for behavior.
- **Ergonomics:** mirrors the mental model of standard HTML (`class` / `style`) and adds first-class `on-*` actions.

---

## 8.2 Core Syntax

```dcz
@style(class="…" style="…" on-click="…" on-hover="…" id="…" data-x="…")
  …content…
@end
```

- All attributes use `key="value"` (equals + double-quote).
- `class` and `style` may be used together. Omit either when not needed.
- Any `on-*` event (e.g. `on-click`, `on-hover`, `on-mouseenter`, `on-keypress`) may be provided.
- Pass-through attributes (like `id`, `title`, `aria-*`, `data-*`) are allowed and forwarded as-is.

The content is wrapped by the renderer (typically a `<span>` in inline contexts, `<div>` in block contexts) with attributes applied. Renderers may choose a consistent element (Docz default: `<span>` for inline, `<div>` for block).

---

## 8.3 CSS Modes

Docz supports two styling modes **without changing directive syntax**:

### 8.3.1 Normal CSS Mode (no Tailwind)

Use `class` and/or `style` like standard HTML.

```dcz
@style(class="blurb" style="color:#0a0; font-weight:600")
  This paragraph is styled with a class plus an inline color.
@end
```

- `class` points to your own CSS (from `@css` blocks or external stylesheets).
- `style` is regular inline CSS (be concise and safe).

### 8.3.2 Tailwind-Enabled Mode

When Tailwind is linked by the toolchain (vendored or monorepo build), utility classes “just work.”

```dcz
@style(class="text-emerald-600 font-semibold")
  Styled entirely with Tailwind utilities.
@end
```

- Prefer `class` with utilities; avoid inline `style` unless absolutely necessary.
- You can still combine with project CSS when you want richer semantics:

```dcz
@style(class="prose prose-lg font-sans my-4")
  Tailwind utilities + prose defaults.
@end
```

> **Guideline:** In Tailwind mode, most styling should live in `class`. In Normal CSS mode, combine `class` + `style` as needed.

---

## 8.4 Actions with `on-*`

Docz lets you attach lightweight interactivity via `on-*` attributes. These map to standard DOM events and are **transport-agnostic**:
they work as **no-op annotations** in static export, and become **live bindings** when a runtime (e.g. Zig/WASM) is enabled.

```dcz
@style(class="button" on-click="incrementCounter")
  Click me
@end
```

- The **name** (`incrementCounter`) is looked up by the runtime integration when WASM is enabled.
- Without a runtime, the attribute is preserved in the HTML for progressive enhancement (your own JS/WASM can bind later).

### 8.4.1 Common Events

- `on-click`, `on-dblclick`
- `on-mouseenter`, `on-mouseleave`, `on-hover` (syntactic sugar; renders as class-toggle or standard event depending on renderer)
- `on-keypress`, `on-keydown`, `on-keyup`
- `on-change`, `on-input`, `on-submit`
- `on-focus`, `on-blur`

> **Note:** Values are **identifiers** or **identifier(args)**. Keep them simple and stable for good portability.

### 8.4.2 Accessibility First

Pair interactions with accessible roles and labels:

```dcz
@style(class="button" role="button" aria-label="Increase count" on-click="incrementCounter")
  +
@end
```

---

## 8.5 Inline vs Block Contexts

`@style` can be used **inline** or as a **block**. The renderer chooses an element that preserves flow:

- Inline: wraps with a `<span …>…</span>`
- Block: wraps with a `<div …>…</div>`

```dcz
# Inline usage
The mass @style(class="font-bold underline") m @end matters.

# Block usage
@style(class="note my-3 p-3 border rounded")
A callout block.
@end
```

---

## 8.6 Composition & Nesting

`@style` can nest and compose:

```dcz
@style(class="card p-4 rounded-lg border")
  @style(class="title text-xl font-semibold") Theorem @end
  @style(class="body text-slate-700")
    If @style(class="font-bold") a @end and @style(class="font-bold") b @end are odd, then a+b is even.
  @end
@end
```

> Nesting compiles to nested elements with clean, deterministic attributes.

---

## 8.7 With `@css` (Global or Local Styles)

Use `@css` for CSS sources; use `@style` to apply them.

```dcz
@css()
.button { padding: 8px 12px; background:#111; color:#fff; border-radius:8px }
.note { background:#fffb; border-left:4px solid #e2e8f0; padding:10px }
@end

@style(class="button") Press @end

@style(class="note") This is a callout. @end
```

When Tailwind is present, you can mix utilities with your classes:

```dcz
@style(class="button inline-flex items-center gap-2")
  @style(class="i-heroicons-plus") @end  Add Item
@end
```

---

## 8.8 Attribute Semantics & Precedence

- **`class`** → appended as-is to the wrapper element.
- **`style`** → emitted as an inline `style` attribute. Avoid conflicting long chains; prefer class-based composition.
- **`on-*`** → emitted as attributes. In static output they remain inert; runtimes may bind them to handlers.
- **`id`, `title`, `aria-*`, `data-*`** → forwarded to output unmodified.
- **Precedence:** Browser CSS rules apply (cascade & specificity). Inline `style` overrides class rules.

---

## 8.9 Escaping & Safety

- Attribute values are HTML-escaped by the compiler (`"` → `&quot;`, `&` → `&amp;`, `<` → `&lt;`, etc.).
- Avoid untrusted string interpolation into `style` to prevent CSS injection vectors.
- In WASM mode, action handlers run in a sandbox by design. Still, treat inputs/data flow with care.

---

## 8.10 Examples (Side-by-Side)

### Normal CSS mode (no Tailwind)

```dcz
@css()
.tip { color:#146; font-weight:600 }
.small { font-size: 12px }
@end

@style(class="tip") Use clear names. @end
@style(class="small" style="letter-spacing:0.2px") Tighter tracking. @end
```

### Tailwind-enabled mode

```dcz
@style(class="text-sky-700 font-semibold") Use clear names. @end
@style(class="text-xs tracking-tight") Tighter tracking. @end
```

### With actions

```dcz
@style(class="btn" on-click="saveDocument")
  Save
@end

@style(class="chip" on-hover="highlightTerm('entropy')")
  entropy
@end
```

---

## 8.11 Authoring Guidance

- **Prefer `class`** for 95% of styling. Keep `style` for small one-offs.
- **Name classes semantically** (`.note`, `.warning`) even if using Tailwind—combine utilities with your own tokens.
- **Co-locate examples**: define minimal CSS in `@css` blocks near where you use them when it helps readability.
- **Progressive enhancement**: your documents should look correct without WASM; WASM adds interaction.

---

## 8.12 Validation Rules (Compiler)

- Only `key="value"` syntax is accepted. (`:` is **not** allowed for assignment in directives.)
- Unknown attributes are forwarded; reserved keys today: `class`, `style`, any `on-*`, `id`, `aria-*`, `data-*`, `title`.
- Empty `@style` content is allowed, but discouraged.
- Attributes must be on the same opening line as `@style(...)`.

---

## 8.13 Quick Reference

| Capability  | Attribute         | Example                                      |
|-------------|-------------------|----------------------------------------------|
| Classes     | `class="…" `      | `@style(class="prose md:prose-lg") … @end`   |
| Inline CSS  | `style="…"`       | `@style(style="color:red") … @end`           |
| Actions     | `on-click="…"`    | `@style(on-click="toggle()") … @end`         |
| Data attrs  | `data-*="…"`      | `@style(data-id="42") … @end`                |
| ARIA        | `aria-*="…"`      | `@style(aria-label="Close") … @end`          |
| IDs/Titles  | `id="…"`, `title` | `@style(id="thm-1" title="Theorem 1") …`     |

**Key point:** You don’t change your document syntax between Normal CSS and Tailwind modes — **Docz takes care of the plumbing**.
