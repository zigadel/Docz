# 5. Inline Directives

Inline directives operate inside paragraphs or spans of text.  
They provide precision without breaking the flow of writing.

Every inline directive has both a **shorthand** form (Markdown‑like) and an **explicit** form (always unambiguous).

---

## 5.1 Emphasis (Bold & Italic)

Shorthand:

```dcz
This is **bold** and *italic* text.
```

Explicit:

```dcz
@bold Bold text @end and @italic italic text @end.
```

---

## 5.2 Inline Code

Shorthand:

```dcz
Use `std.debug.print` in Zig.
```

Explicit:

```dcz
@code-inline lang="zig" std.debug.print @end
```

---

## 5.3 Links

Shorthand:

```dcz
[Zig Language](https://ziglang.org)
```

Explicit:

```dcz
@link(href:"https://ziglang.org") Zig Language @end
```

---

## 5.4 Inline Math

Shorthand (LaTeX‑style):

```dcz
The equation is $F = ma$.
```

Explicit:

```dcz
@math-inline F = ma @end
```

---

## 5.5 Inline Styling

You can apply classes, styles, or actions inline:

```dcz
Energy is @style(class:"highlight") E @end = mc^2
```

This compiles to:

```html
Energy is <span class="highlight">E</span> = mc^2
```

---

## 5.6 Why Inline Directives Matter

Inline directives give Docz documents:

- **Clarity**: unambiguous parsing compared to Markdown edge cases.
- **Consistency**: inline and block forms share the same directive system.
- **Power**: you can combine text, math, styling, and links seamlessly.
