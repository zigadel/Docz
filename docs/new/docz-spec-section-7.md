# 7. Styling in Docz

Styling is a first-class citizen in Docz. Documents are meant to be both expressive and beautiful, without forcing writers to leave the flow of text.

Docz provides two complementary approaches to styling:

1. **Core Styling** – via `docz.core.css`, which gives every document a strong typographic foundation.
2. **Custom Styling** – via directives like `@style`, global `@css`, and theme extensions (e.g., Tailwind).

---

## 7.1 Core Styling

Every Docz render includes a baseline stylesheet:

- `docz/assets/css/docz.core.css`  
- Defines typographic rhythm, spacing, and defaults for headings, paragraphs, code, and math.  
- Provides a consistent, professional look without any configuration.

This ensures that **every `.dcz` file looks good out of the box** — even without extra themes.

---

## 7.2 The `@style` Directive

Use `@style` when you want to apply inline or block-level styles.

### 7.2.1 Example (Inline)

```dcz
Energy is @style(class:"highlight") E @end = mc^2
```

Compiles to:

```html
Energy is <span class="highlight">E</span> = mc^2
```

### 7.2.2 Example (Block)

```dcz
@style(class="note")
This entire paragraph is styled as a note.
@end
```

Compiles to:

```html
<p class="note">This entire paragraph is styled as a note.</p>
```

---

## 7.3 Shorthand Styling

To avoid verbosity, Docz provides a shorthand form for inline styling:

```dcz
The result is @{"highlight"|E} = mc^2
```

This is equivalent to the `@style(class:"highlight")` directive.

---

## 7.4 Global Styles with `@css`

For larger documents, you can define reusable, global CSS rules using `@css`:

```dcz
@css
.note { background: #fffae6; padding: 0.5rem; border-left: 4px solid #f5b700; }
.highlight { font-weight: bold; color: red; }
@end
```

Compiles to a `<style>` block in the `<head>` of the HTML output.

---

## 7.5 Themes and Tailwind

Docz supports theming at two levels:

1. **Vendored TailwindCSS Theme** – included out-of-the-box and automatically linked if detected.  
2. **Custom Themes** – drop in any `.css` file or extend Tailwind via `@css`.  

Examples:

- Monorepo build: `themes/default/dist/docz.tailwind.css`  
- Vendored theme: `third_party/tailwind/docz-theme-*/css/docz.tailwind.css`  

---

## 7.6 Why Styling Matters

- **Uniformity:** `@style`, `@css`, and shorthand syntax are consistent everywhere.  
- **Flexibility:** works with plain CSS *and* Tailwind extensions.  
- **Determinism:** unlike Markdown extensions, every style directive compiles into predictable HTML+CSS.

With styling, Docz documents can be **minimalist notes** or **full-blown interactive textbooks** — without ever leaving `.dcz`.
