# 6. Inline Directives

Inline directives in Docz operate within the flow of text. They are lighter than block directives and are used to modify or annotate parts of a paragraph without breaking structure. They make documents expressive while remaining compact and uniform.

## 6.1 Syntax

Inline directives follow the same form as block directives, but their content is limited to inline text.

```dcz
This is @style(class:"highlight") important @end text.
```

## 6.2 Shorthand Equivalents

For common inline patterns, Markdown-inspired shorthand exists:

- **Bold:** `**bold**` ⇔ `@b bold @end`
- **Italic:** `*italic*` ⇔ `@i italic @end`
- **Inline code:** `` `code` `` ⇔ `@code-inline lang:"text" code @end`
- **Links:** `[Zig](https://ziglang.org)` ⇔ `@link(href:"https://ziglang.org") Zig @end`
- **Inline math:** `$E=mc^2$` ⇔ `@math-inline E=mc^2 @end`

## 6.3 Examples

```dcz
Energy is $E = mc^2$ where @style(class="important") mass @end plays the key role.

For more details, visit [Zig](https://ziglang.org) or read the `README.dcz` file.
```

## 6.4 Why Inline Directives Matter

Inline directives unify Docz by extending the same directive model used for blocks into the flow of text:

- **Clarity:** every inline modification is explicit and parseable.
- **Flexibility:** shorthand accelerates writing; directives guarantee precision.
- **Consistency:** no special cases; inline math, styles, and links follow the same rules.

Inline directives allow `.dcz` documents to remain readable and ergonomic, while ensuring the underlying structure is deterministic and suitable for AI parsing, transformations, and reliable HTML export.
