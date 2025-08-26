# 4. Block Directives

Docz provides block-level constructs for the most common document patterns.  
Every block directive has **two forms:**

1. **Shorthand** (Markdown-inspired, ergonomic for humans)  
2. **Explicit form** (always valid, fully general, preferred by compilers/transformers, and guaranteed unambiguous for AI/LLMs)

This duality gives writers flexibility: you can draft fast in shorthand, then “convert to explicit” with the `--explicit` flag if you want a canonical representation.

---

## 4.1 Headings

Headings provide structure to your document.  
They are among the most common elements in technical writing.

**Shorthand:**

```dcz
# Level 1 Heading
## Level 2 Heading
### Level 3 Heading
```

**Explicit:**

```dcz
@heading(level=1) Level 1 Heading @end
@heading(level=2) Level 2 Heading @end
@heading(level=3) Level 3 Heading @end
```

---

## 4.2 Paragraphs

Paragraphs are blocks of prose separated by blank lines.  
They are the default structure for running text.

**Shorthand:**

```dcz
This is a paragraph.
It continues on the next line.

This is a new paragraph.
```

**Explicit:**

```dcz
@p
This is a paragraph.
It continues on the next line.
@end

@p
This is a new paragraph.
@end
```

---

## 4.3 Code Blocks

Code blocks allow fenced sections of source code with optional language tagging.  
They are **escaped**, preserving whitespace and preventing unintended parsing.

**Shorthand:**

```dcz
@code(lang:"zig")
const std = @import("std");
pub fn main() void {
    std.debug.print("Hello, world!\n", .{});
}
@end
```

**Explicit (identical, since shorthand is already directive form):**

```dcz
@code(lang:"zig")
const std = @import("std");
pub fn main() void {
    std.debug.print("Hello, world!\n", .{});
}
@end
```

---

## 4.4 Math Blocks

Math is rendered using **KaTeX** when available.  
Block math supports LaTeX syntax between the directive.

**Shorthand:**

```dcz
@math
E = mc^2
@end
```

**Explicit (identical to shorthand):**

```dcz
@math
E = mc^2
@end
```

**Inline math** uses `$...$` shorthand or `@math.inline(...)` explicitly.

---

## 4.5 Lists

Docz supports ordered and unordered lists.

**Unordered list (shorthand):**

```dcz
- Item one
- Item two
  - Nested item
```

**Explicit:**

```dcz
@list(type:"unordered")
- Item one
- Item two
  - Nested item
@end
```

**Ordered list (shorthand):**

```dcz
1. Step one
2. Step two
```

**Explicit:**

```dcz
@list(type:"ordered")
1. Step one
2. Step two
@end
```

---

## 4.6 Quotes / Blockquotes

Blockquotes allow emphasis of quoted text.

**Shorthand:**

```dcz
> This is a quoted block of text.
```

**Explicit:**

```dcz
@quote
This is a quoted block of text.
@end
```

---

## 4.7 Tables (via Plugins)

Docz includes table support through the **ZTable plugin**.

**Shorthand:**

```dcz
| Name   | Value |
|--------|-------|
| Mass   | 5kg   |
| Energy | mc^2  |
```

**Explicit:**

```dcz
@table
| Name   | Value |
|--------|-------|
| Mass   | 5kg   |
| Energy | mc^2  |
@end
```

---

## 4.8 Graphs (via Plugins)

Docz supports graph definitions using the **ZGraph plugin**.

```dcz
@graph(type:"directed")
A -> B
B -> C
@end
```

This produces an embeddable graph visualization, powered by a plugin.

---

## 4.9 Why Block Directives Matter

Block directives give Docz its **power and extensibility**:

- You can write minimal Markdown-style text, but always have a clear explicit equivalent.
- Blocks cover 90% of technical writing needs: headings, paragraphs, code, math, lists, tables, and graphs.
- Each block maps to **deterministic HTML+CSS**, ensuring documents are unambiguous for both humans and AI.

Block directives are the **foundation**. Inline directives layer on top of them for finer-grained styling and semantics.
