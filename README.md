# Docz

A fast, ergonomic documentation engine and file format designed for STEM writing. Docz blends a crisp authoring experience with the power of HTML/CSS, optional TailwindCSS, KaTeX math, and (optionally) Zig/WASM for advanced scenarios. It aims to be **presentable by default** while remaining **extensible** and **maintainable** over the long haul.

---

## Why Docz?

- **Clean defaults, power on tap** – Write with simple, readable shorthand; get professional output instantly. Drop to HTML/CSS/Tailwind when you need full control.
- **A real language** – `.dcz` files compile via a tokenizer → parser → renderer pipeline. The CLI gives you repeatable builds.
- **Live preview** – Local web server with hot reload for a smooth “edit → see” loop.
- **Vendored assets** – Reproducible builds via `third_party/` (KaTeX, theme CSS). No flaky CDNs.
- **Monorepo** – One place for engine, preview server, tests, examples, and VSCode extension.

---

## Key Features

- **First‑class `.dcz`**: compact directives with readable defaults.
- **Shorthand inline styling** in prose (rendered post‑export):
  - `**bold**`, `*italic*`, `__underline__`, `[text](url)`, headings with `#`, `##`, `###`, …
- **Directives** (baseline set):
  - `@meta(title:"...", author:"...")` → document metadata (used in `<title>`)
  - `@style(mode:"global") … @end` → quick style hints
  - `@math … @end` → KaTeX rendering (display math)
  - `@code(lang:"zig") … @end` → code blocks with language classes
  - (Additional directives and plugins can be added over time.)
- **Automatic assets**:
  - Core CSS (`assets/css/docz.core.css`) always injected first
  - Optional external CSS file (if you ask for `--css file`)
  - Vendored Tailwind theme (`third_party/tailwind/.../docz.tailwind.css`) when available
  - KaTeX CSS/JS (from `third_party/katex/...`) injected when present
- **Web Preview**: lightweight HTTP server (`docz preview`) serving compiled output and `third_party/` assets with hot reload support.
- **VSCode Extension**: syntax highlighting and (future) editor ergonomics for `.dcz`.

---

## Repository Layout

```
docz/
├─ assets/                     # Core assets (e.g., docz.core.css)
├─ docs/                       # Project docs, spec, guide
├─ examples/                   # Small sample .dcz inputs
├─ src/
│  ├─ cli/                     # CLI subcommands (build, run, preview, convert, ...)
│  ├─ convert/                 # Import/export bridges (HTML/Markdown/LaTeX)
│  ├─ parser/                  # Tokenizer, AST, Parser
│  ├─ renderer/                # HTML renderer (and helpers)
│  ├─ core/                    # (future core pieces live here)
│  └─ main.zig                 # Entry point wiring the CLI
├─ themes/default/             # Optional Tailwind theme (local build)
│  ├─ src/                     # Tailwind input/preflight
│  ├─ dist/                    # Built CSS (docz.tailwind.css)
│  └─ tailwind.config.js
├─ third_party/                # Vendored, checksummed assets
│  ├─ katex/<ver>/dist/...
│  └─ tailwind/docz-theme-<ver>/css/docz.tailwind.css
├─ tools/
│  ├─ vendor.zig               # Vendoring/bootstrap tool (fetch/verify/freeze)
│  └─ vendor.config            # Manifests + settings
├─ web-preview/                # Preview server (routes, hot reload)
├─ vscode-extension/           # VSCode extension (basic syntax highlighting)
├─ tests/                      # Unit, integration, e2e tests
├─ build.zig                   # Zig build script
└─ root.zig                    # Library surface exports (Tokenizer/Parser/Renderer/etc.)
```

---

## Quick Start

### Prerequisites

- **Zig**: use the project’s documented toolchain (tested with `0.15.0-dev` lineage).
- **Node.js + npm** (optional): only if you want to rebuild the local Tailwind theme under `themes/default/`.

### Build & Test

```bash
# From repo root
zig build test-all --summary all
```

You should see all unit/integration/e2e tests pass. Tests are your safety net for refactors.

### Vendor Third‑Party Assets (recommended once)

```bash
zig build vendor
```

This will:
- Fetch KaTeX into `third_party/katex/<version>/dist/...`
- Place the Docz Tailwind theme into `third_party/tailwind/docz-theme-<version>/css/docz.tailwind.css`
- Write checksums and a `third_party/VENDOR.lock` for reproducibility

### Preview a Document

```bash
# Live compile + serve + auto‑reload
zig build run -- run ./examples/hello.dcz
```

This compiles to a temp dir (`.zig-cache/docz-run/`), starts the preview server on your configured port (default `5173`), opens the browser, and hot‑reloads on file changes.

### Standalone Preview Server

```bash
zig build run -- preview
# or with options
zig build run -- preview --root docs --port 8787 --no-open
```

The server also serves `third_party/*` under the `/third_party/...` route for deterministic local assets.

---

## CLI Reference (stable subset)

> Run `zig build run --` to see top–level help. Below are the primary subcommands.

### `docz run <file.dcz> [--port <n>] [--css inline|file] [--no-pretty] [--no-live] [--config <file>]`

- Compiles the given `.dcz` to HTML in a temp directory and serves it via the preview server.
- Options:
  - `--port <n>`: overrides port used by `docz preview`
  - `--css inline|file`: keep CSS inline or emit `docz.css` and link it
  - `--no-pretty`: skip HTML pretty-print pass
  - `--no-live`: disable hot reload marker
  - `--config <file>`: load `docz.settings.json` from a custom path

### `docz preview [<path>] [--root <dir>] [--port <n>] [--no-open] [--config <file>]`

- Serves a directory (default `.`) and optionally opens `docs/SPEC.dcz` (or a provided file) in the browser.
- Designed to work with `docz run`, but useful standalone too.

### `docz enable wasm`

- Toggle scaffolding for WASM execution if/when your pipeline uses Zig+WASM runtime features. (Experimental placeholder.)

> Additional converters (HTML/Markdown/LaTeX round‑trips) live under `src/convert/` and are wired into the CLI where practical. Check `tests/integration/` for current capabilities.

---

## Configuration

Docz looks for `docz.settings.json` in the working directory by default (you can point to another file with `--config`). Minimal example:

```json
{
  "port": 5173
}
```

The CLI merges explicit flags over config values. For example, `--port 8787` wins over the JSON value.

---

## Styling & Assets

### CSS Order of Operations

1. **Core CSS** – embedded into the build and always written as `docz.core.css`, linked first.
2. **Your external CSS** (if `--css file`) – collected from inline styles and written as `docz.css`, linked second.
3. **Tailwind Theme** – if available, `docz.tailwind.css` is copied from either:
   - `themes/default/dist/docz.tailwind.css` (preferred, if present), or
   - latest vendored `third_party/tailwind/docz-theme-*/css/docz.tailwind.css`.
   Linked last, so it can override earlier rules if needed.
4. **KaTeX** – when `third_party/katex/*/dist` is present, its CSS/JS are injected and `auto-render` is enabled with common delimiters (`$...$`, `$$...$$`, `\(...\)`, `\[...\]`).

### Building the Local Theme (optional)

If you want to iterate on `themes/default/`:

```bash
cd themes/default
npm install
npm run build     # produces dist/docz.tailwind.css
```

`docz run` will prefer this file when present.

---

## `.dcz` Authoring Basics

A tiny taste of the current baseline (see `examples/` for more):

```text
@meta(title:"Docz Hello", author:"You")

@style(mode:"global")
heading-level-1: font-size=36px, font-weight=bold
body-text: line-height=1.6
@end

# Hello, Docz!
This is **bold**, *italic*, __underline__, and a [link](https://ziglang.org).

@math
E = mc^2
@end

@code(lang:"zig")
const std = @import("std");
pub fn main() !void { std.debug.print("hi\n", .{}); }
@end
```

Docz currently applies a pragmatic fallback renderer that:
- Converts headings `#..######` to `<h1>..</h1>`…`<h6>..</h6>`
- Converts inline marks `**`, `*`, `__`, and `[text](url)` outside of `pre/code/script/style`
- Handles display math via KaTeX when `@math ... @end` blocks are present
- Emits `<pre><code class="language-...">` for `@code(lang:"...")`

The full tokenizer/parser/renderer pipeline is tested and evolving—expect the fallback renderer to be replaced by the full pipeline as we complete directive coverage.

---

## Web Preview

- Serves static output and `/third_party/...` assets
- Hot-reload marker (`__docz_hot.txt`) is polled by an injected `<script>` unless disabled with `--no-live`
- Robust path sanitization and a simple MIME resolver for common types

---

## Testing

Docz ships with unit, integration, and end‑to‑end tests.

```bash
zig build test-all --summary all   # everything
zig build test                     # unit-only (if configured)
```

When debugging memory issues, Zig’s GPA diagnostics will flag double‑frees, leaks, and unbalanced alloc/dealloc. Tests are written to pass cleanly (no leaks) under GPA.

---

## Troubleshooting

- **`npm ci` fails** – The local theme uses `npm install` the first time to generate a lockfile; `npm ci` requires an existing lockfile.
- **Formatting placeholders** – When using `std.fmt.allocPrint`, remember to escape braces in embedded JavaScript/JSON with doubled braces: `{{` and `}}`.
- **Windows paths** – Use forward slashes when constructing URLs for the preview server. The code handles OS path joins internally.
- **Vendoring** – If `zig build vendor` complains about missing files, delete `third_party/` and re‑run; ensure your network allows the downloads listed in `tools/vendor.config`.

---

## Contributing

- See [`.github/CONTRIBUTING.md`](./.github/CONTRIBUTING.md) and the issue templates under `.github/ISSUE_TEMPLATE/`.
- All changes should keep tests green; add tests for new features.
- Prefer small, focused PRs.
- Keep the CLI help text accurate and user‑oriented.

---

## Roadmap

High‑level direction is tracked in:
- [`docs/ROADMAP.md`](./docs/ROADMAP.md)
- [`docs/SPEC.dcz`](./docs/SPEC.dcz)
- [`docs/PLUGIN_GUIDE.md`](./docs/PLUGIN_GUIDE.md)

Planned areas:
- Full directive coverage via the tokenizer/parser/renderer pipeline
- First‑class tables/graphs (`@table`, `@graph`)
- Stronger plugin system and WASM execution hooks
- Theme packs and richer default typography

---

## Acknowledgements

- **Zig** – A joyfully low‑level, precise language that makes writing fast, correct tooling a delight.
- **TailwindCSS** – For utility‑first CSS; used optionally by Docz themes.
- **KaTeX** – For blazing‑fast math rendering.

---

## License

TBD.
