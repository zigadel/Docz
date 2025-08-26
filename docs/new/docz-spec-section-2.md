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
    std.debug.print("Hello from Zig!\n", .{});
}
@end
```

## 2.2 What’s Happening Here

- `#` starts a heading — shorthand for `@heading(level=1)`.
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
