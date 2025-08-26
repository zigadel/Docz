# DCZ File Specification

Docz (`.dcz`) is a document language and toolchain designed to make technical writing — from STEM notes and research papers to specs, guides, and documentation — as clear, fast, and programmable as possible.  

It combines the familiarity of Markdown with the precision of LaTeX and the interactivity of Jupyter notebooks, while avoiding their limitations.  

---

## 1. Introduction

### 1.1 What Docz Gives You
- **Markdown-like brevity** for everyday writing (headings, lists, links).
- **First-class math, code blocks, and styling** through declarative `@directives`.
- **Deterministic compilation** to clean HTML that is portable, themeable, and easy to style.
- **Optional power-ups:** Tailwind themes, KaTeX math, syntax highlighting, and live preview out of the box.

Docz lets you stay **minimal when you want brevity** — and **explicit when you need precision**.

### 1.2 Why Docz Exists
Existing tools fall short:
- **Markdown** is convenient, but underspecified and inconsistent.
- **LaTeX** is precise, but verbose and brittle.
- **Jupyter** is interactive, but locked to Python and hard to version cleanly.

Docz unifies the strengths of all three: **simplicity, clarity, interactivity, portability**.

### 1.3 Core Philosophy
- **Clarity first:** documents should be easy to read and easy to parse (for humans and AI).
- **Explicit over clever:** everything has an explicit form; shorthand is optional.
- **Programmable by design:** text and computation should coexist naturally.

**Future-proof:** Docz compiles to standard HTML+CSS+WASM — formats that will outlive any single framework.

### 1.4 Programmability via WASM
Docz is not just about text and formatting. It is also a programmable document format.  

Through **WebAssembly (WASM)**, `.dcz` files can embed live, sandboxed code that executes at render time.
- **Zig-first:** Docz is written in Zig, and Zig compiles to WASM seamlessly. Zig is the first-class supported language for inline execution.
- **Language-agnostic by design:** Any language that targets WASM (Rust, C, Go, AssemblyScript, etc.) can run in Docz.
- **Beyond Markdown/LaTeX/Jupyter:** Markdown and LaTeX stop at formatting. Jupyter binds you to Python.  
Docz, with WASM enabled, lets you compute, visualize, and interact in a **portable**, **deterministic**, **language-agnostic way**.

---

## 2. Quick Glimpse

The best way to understand Docz is to see it in action.  
Here’s a short `.dcz` snippet — **real Docz code** that compiles directly to clean HTML:

```dcz
@meta(title="Physics Notes", author="Ada Lovelace")

# Energy Basics

**Einstein’s insight**:  

@math
E = mc^2
@end

@style(class="highlight")
This equation shows how mass and energy are interchangeable.
@end

## Experiment Setup

- Write equations inline: $F = ma$
- Link like Markdown: [Zig](https://ziglang.org)
- Code with language tags:

@code(lang="zig")
const std = @import("std");
pub fn main() void {
    std.debug.print("Hello from Zig!\n", .{});
}
@end
```

### 2.2 What’s Happening Here
- `#` starts a heading — shorthand for `@heading(level=1)`.
- `@math ... @end` renders KaTeX display math.
- `@style(class="highlight") ... @end` applies styling.
- Inline `$...$` math works like LaTeX.
- Links and emphasis follow Markdown shorthand.
- `@code(lang="zig") ... @end` produces syntax-highlighted, escaped code blocks.

### 2.3 Why This Matters
- **Uniformity:** shorthand (`#`) and explicit (`@heading`) are equivalent.  
- **Power at hand:** math, code, styling, metadata are all first-class.  
- **Clarity:** every feature compiles to clean, unambiguous HTML+CSS.  

Docz feels like **Markdown 2.0**: the same speed, but with **mathematical rigor**, **styling control**, and **programmability** built in.

---

## 3. Directives Overview

Directives are the core building blocks of Docz.  
They look like this:

```less
@name(attr="value", attr2="value2")
   content…
@end
```

Every directive has:
- **A name** (e.g. `style`, `code`, `math`).
- **Optional attributes** in `key="value"` form.
- **Content** between the opening line and `@end`.

Think of directives as **programmable Markdown blocks** — they extend what Markdown can do, but remain lightweight and intuitive.

### 3.1 Shorthand vs Explicit
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

### 3.2 Inline vs Block
- **Inline directives** work inside text:  
```dcz
Energy is @style(class="important") E @end = mc^2
```

- **Block directives** create larger structures:  
```dcz
@math
E = mc^2
@end
```

This separation makes Docz easy to scan — inline when light, block when heavy.

---

## 4. Block Directives

### 4.1 Headings
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

### 4.2 Paragraphs
Shorthand:
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

### 4.3 Code Blocks
```dcz
@code(lang="zig")
const std = @import("std");
pub fn main() void {
    std.debug.print("Hello, world!\n", .{});
}
@end
```

### 4.4 Math Blocks
```dcz
@math
E = mc^2
@end
```

### 4.5 Style Blocks
```dcz
@style(class="note")
This text is highlighted as a note.
@end
```

---

## 5. Inline Directives

- `@style(class="highlight") ... @end` — highlight inline text.  
- Inline math: `$a^2 + b^2 = c^2$`.  
- Inline code: `` `code` ``.  

---

## 6. Metadata & Imports
```dcz
@meta(title="Docz Guide", author="Docz Authors", date="2025-08-26")
@end
```

```dcz
@import(path="./other.dcz")
@end
```

---

## 7. Styling & Themes

- **Core CSS:** included by default (`docz.core.css`).  
- **Optional TailwindCSS themes:** vendored or monorepo-built.  
- **Custom Themes:** pluggable via directives and config.  

---

## 8. Interactivity & Actions

Docz supports **HTML-like events**:  
```dcz
@style(class="button" on-click="incrementCounter")
Click me!
@end
```

- Works in **CSS-only mode** for styling.
- With **WASM enabled**, handlers can run Zig/Rust/etc. code.  
- `on-click`, `on-hover`, `on-focus`, etc.  

---

## 9. Extensibility & Plugins
- `@table` → backed by **ZTable plugin**.  
- `@graph` → backed by **ZGraph plugin**.  
- Plugin API: import, register, and extend Docz.  

---

## 10. CLI Overview

```bash
docz build <file.dcz>       # Build .dcz file to HTML
docz preview                # Start local preview server
docz convert input.dcz --explicit   # Normalize to explicit form
docz run <file.dcz>         # Build + preview
```

---

## 11. Philosophy Recap
- **Markdown-like ergonomics.**
- **LaTeX-grade math.**
- **Jupyter-like programmability.**
- **Portable HTML+CSS+WASM output.**

**Docz is built to be the de facto format for all things STEM.**
