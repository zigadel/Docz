# 3. Directives Overview

Directives are the core building blocks of Docz.
They look like this:

```less
@name(attr:"value", attr2:"value2")
   content…
@end
```

Every directive has:
- **A name** (e.g. `style`, `code`, `math`).
- **Optional attributes** in `key:"value"` form.
- **Content** between the opening line and `@end`.

Think of directives as **programmable Markdown blocks** — they extend what Markdown can do, but remain lightweight and intuitive.

## 3.1 Shorthand vs Explicit

Docz allows two styles:

**Shorthand (Markdown-like):**
```dcz
# Heading 1
```

**Explicit (Directive form):**
```dcz
@heading(level=1)
Heading 1
@end
```

Both produce the same output.
Shorthand is great for **speed of writing**, while directives provide **precision & extensibility**.

## 3.2 Inline vs Block

- **Inline directives** work inside text:
    ```dcz
    Energy is @style(class:"important") E @end = mc^2
    ```
- **Block directives** create larger structures:
    ```dcz
    @math
    E = mc^2
    @end
    ```

This separation makes Docz easy to scan — inline when light, block when heavy.

## 3.3 Example Side-by-Side

```dcz
# Inline Example
The force is $F = ma$ and @style(class:"highlight") mass @end is key.

# Block Example
@code(lang:"bash")
zig build run -- run ./hello.dcz
@end
```

## 3.4 Why Directives Work

Directives give Docz **determinism**:

- Every `@` block is explicit, structured, and parseable.
- Shorthand is just `syntactic sugar` for directives.
- Parsing is `AI and human-friendly`: no ambiguity, unlike Markdown’s edge cases.

---

So far, the reader has seen shorthand and directives side by side.
They’ve learned:

- Everything in Docz is a directive.
- Shorthand is optional but ergonomic.
- The syntax is **uniform**, **predictable**, and **extensible**.
