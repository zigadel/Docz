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
- **Markdown** is convenient, but underspecified and inconsistent.
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
