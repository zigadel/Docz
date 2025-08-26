# 1. Introduction

Docz is a **document language and toolchain** designed to make technical writing — from STEM notes and research papers to specs, guides, and documentation — **as clear, fast, and programmable as possible**.

It combines the familiarity of Markdown with the precision of LaTeX and the interactivity of Jupyter notebooks, while avoiding their limitations.

## 1.1 What Docz Gives You
- **Markdown-like brevity** for everyday writing (headings, lists, links).
- **First-class math, code blocks,** and **styling** through declarative `@directives`.
- **Deterministic compilation** to clean HTML that is portable, themeable, and easy to style.
- **Optional power-ups:** Tailwind themes, KaTeX math, syntax highlighting, and live preview out of the box.

Docz lets you stay **minimal when you want brevity** — and **explicit when you need precision**.

## 1.2 Why Docz Exists

Existing tools fall short:
- **Markdown** is covenient , but underspecified and inconsistent.
- **LaTeX** is precise, but verbose and brittle.
- **Jupyter** is interactive, but locked to Python and hard to version cleanly.

Docz unifies the strengths of all three: **simplicity, clarity, interactivity, portability**.

## 1.3 Core Philosophy

Docz is built on a few guiding principles:
- **Clarity first:** documents should be easy to read and easy to parse (for humans and AI).
- **Explicit over clever:** everything has an explicit form; shorthand is optional.
- **Programmable by design:** text and computation should coexist naturally.

**Future-proof:** Docz compiles to standard HTML+CSS+WASM — formats that will outlive any single framework.

## 1.4 Programmability via WASM

Docz is not just about text and formatting. It is also a programmable document format.
Through **WebAssembly (WASM)**, `.dcz` files can embed live, sandboxed code that executes at render time.
- **Zig-first:** Docz is written in Zig, and Zig compiles to WASM seamlessly. Zig is the first-class supported language for inline execution.
- **Language-agnostic by design:** Any language that targets WASM (Rust, C, Go, AssemblyScript, etc.) can run in Docz.
- **Beyond Markdown/LaTeX/Jupyter:** Markdown and LaTeX stop at formatting. Jupyter binds you to Python.
Docz, with WASM enabled, lets you compute, visualize, and interact in a **portable**, **deterministic**, **language-agnostic way**.

Docz is thus not only a **replacement** for Markdown and LaTeX, but also a **superset** of the interactive notebook paradigm — blending text, math, and live computation in a single universal format.

# 2. Quick Glimpse

The best way to understand Docz is to see it in action.
Here’s a short `.dcz` snippet — **real Docz code** that compiles directly to clean HTML:

## 2.1 Example

```dcz
@meta(title:"Physics Notes", author:"Ada Lovelace")

# Energy Basics

**Einstein’s insight**:  

@math
E = mc^2
@end

@style(class:"highlight")
This equation shows how mass and energy are interchangeable.
@end

## Experiment Setup

- Write equations inline: $F = ma$
- Link like Markdown: [Zig](https://ziglang.org)
- Code with language tags:

@code(lang:"zig")
const std = @import("std");
pub fn main() void {
    std.debug.print("Hello from Zig!\\n", .{});
}
@end
```

## 2.2 What’s Happening Here

- `#` starts a heading — shorthand for @heading(level=1).
- `@math ... @end` renders KaTeX display math.
- `@style(class:"highlight") ... @end` applies styling.
- `Inline $...$` math works like LaTeX.
- Links and emphasis follow Markdown shorthand.
- `@code(lang:"zig") ... @end` produces syntax-highlighted, escaped code blocks.

## 2.3 Why This Matters

**Uniformity:** shorthand (`#`) and explicit (`@heading`) are equivalent. Use whichever fits.

**Power at hand:** math, code, styling, metadata are all first-class.

**Clarity:** every feature compiles to clean, unambiguous HTML+CSS.

Docz feels like **Markdown 2.0**: the same speed, but with **mathematical rigor**, **styling control**, and **programmability** built in.

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

# 4. Block Directives

Docz provides block-level constructs for the most common document patterns. Every block directive has **two forms:**

1. **Shorthand** (Markdown-inspired, ergonomic for humans)
2. **Explicit form** (always valid, fully general, preferred by compilers/transformers, and guaranteed unambiguous for AI/LLMs)

This duality gives writers flexibility: you can draft fast in shorthand, then “convert to explicit” with the --explicit flag if you want a canonical representation.

## 4.1 Headings

Shorthand:

```dcz
# Level 1 Heading
## Level 2 Heading
### Level 3 Heading
```

Explicit:

```dcz
@heading(level=1) Level 1 Heading @end
@heading(level=2) Level 2 Heading @end
@heading(level=3) Level 3 Heading @end
```

## 4.2 Paragraphs

Shorthand:

Any line of text separated by a blank line is a paragraph.

```dcz
This is a paragraph.
It continues on the next line.

This is a new paragraph.
```

Explicit:

```dcz
@p
This is a paragraph.
It continues on the next line.
@end

@p
This is a new paragraph.
@end
```

## 4.3 Code Blocks
s
```dcz
@code(lang="zig")
const std = @import("std");
pub fn main() void {
    std.debug.print("Hello, world!\n", .{});
}
@end
```