# 9. Lists

Lists are a core building block of technical writing. Docz supports both the **shorthand Markdown-like syntax** and the **explicit directive form**, ensuring clarity, flexibility, and AI-friendly parsing.

## 9.1 Unordered Lists

**Shorthand (Markdown-inspired):**

```dcz
- First item
- Second item
- Third item
```

**Explicit form:**

```dcz
@ul
  @li First item @end
  @li Second item @end
  @li Third item @end
@end
```

Both forms compile to the same clean HTML:

```html
<ul>
  <li>First item</li>
  <li>Second item</li>
  <li>Third item</li>
</ul>
```

## 9.2 Ordered Lists

**Shorthand:**

```dcz
1. First step
2. Second step
3. Third step
```

**Explicit form:**

```dcz
@ol
  @li First step @end
  @li Second step @end
  @li Third step @end
@end
```

Compiles to:

```html
<ol>
  <li>First step</li>
  <li>Second step</li>
  <li>Third step</li>
</ol>
```

## 9.3 Nested Lists

Docz allows nesting lists naturally.  
You may use shorthand or explicit forms, or mix them as needed.

```dcz
- First
  - Nested A
  - Nested B
- Second
```

Explicit:

```dcz
@ul
  @li First
    @ul
      @li Nested A @end
      @li Nested B @end
    @end
  @end
  @li Second @end
@end
```

Which compiles to properly nested HTML:

```html
<ul>
  <li>First
    <ul>
      <li>Nested A</li>
      <li>Nested B</li>
    </ul>
  </li>
  <li>Second</li>
</ul>
```

## 9.4 Mixed Content in List Items

List items may contain **paragraphs, math, code, or any block directive.**

Example:

```dcz
- Introductory text

  @math
  E = mc^2
  @end

- Inline code example: `zig build run`
```

This allows complex documentation patterns without breaking list semantics.

## 9.5 Styling Lists

Lists (and list items) accept `class`, `style`, and interaction attributes:

```dcz
@ul(class="checklist")
  @li(style="color:red") Important item @end
  @li(on-click="markDone") Clickable item @end
@end
```

Which becomes:

```html
<ul class="checklist">
  <li style="color:red">Important item</li>
  <li data-on-click="markDone">Clickable item</li>
</ul>
```

## 9.6 Accessibility Considerations

Docz always preserves correct semantic HTML for lists (`<ul>`, `<ol>`, `<li>`).  
This ensures that screen readers, search engines, and accessibility tools behave as expected.  
Styling directives should never strip away these semantics.

---

**Summary:**  
- Use shorthand (`-`, `1.`) for speed.  
- Use directives (`@ul`, `@ol`, `@li`) for precision and attributes.  
- Nesting and mixed content are supported.  
- Accessibility and semantics are guaranteed.  
