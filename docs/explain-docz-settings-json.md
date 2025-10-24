# Understanding `docz.settings.json`

This guide explains every field in `docz.settings.json`, how it affects **Docz** behavior, and why the defaults are chosen. It’s written to be practical: skim a section, change a key, and know exactly what will happen.

---

## Top-level

### `root`
Project root directory used for resolving paths. `"."` means the repository root.

---

## `preview` — Local web server

Controls the built‑in preview server behavior.

- **`host`**: Network interface to bind. Use `127.0.0.1` for local only, `0.0.0.0` to expose on LAN.
- **`port`**: Port to listen on. `0` = pick a free ephemeral port (best for CI and parallel tests).
- **`open`**: If `true`, opens your browser to the preview URL on startup.
- **`strict_mime`**: Serve correct MIME types and block ambiguous ones (reduces browser quirks and XSS risk).
- **`compression`**: HTTP compression knobs.
  - `gzip`: Common, broadly supported.
  - `brotli`: Smaller output, optional.
- **`cache`**:
  - `etag`: Issue/validate ETags so the browser can use `304 Not Modified` responses.
  - `immutable_third_party`: Mark vendored assets as long‑lived and immutable (safe because filenames are content‑hashed).

---

## `build` — Static export / convert

Affects `docz build` and `docz convert` outputs.

- **`out_dir`**: Output directory for built files.
- **`hash_assets`**: Content‑hash filenames (`file.<sha>.css/js`) for perfect cache‑busting.
- **`integrity`**: Subresource Integrity algorithm for `<link>`/`<script>` (e.g., `"sha256"`). Browsers verify the file before using it.
- **`sourcemaps`**: Generate source maps for JS/CSS in builds.
- **`katex`**: Math render mode for `@math`.
  - `"server"`: Render KaTeX to HTML during build (self‑contained exports).
  - (Future) `"client"`: Render in the browser.
- **`minify_html`**: Minify final HTML (trade readability for size).

---

## `third_party` — Vendored dependencies

Paths and expectations for vendored assets (e.g., KaTeX, Tailwind).

- **`root`**: Directory that contains vendored packages.
- **`katex_version`**: Expected KaTeX version (used for verification).
- **`tailwind_theme_glob`**: Pattern used to auto‑select a prebuilt Tailwind theme CSS. Docz picks the newest match.

---

## `theme` — How CSS is chosen

Determines which stylesheet Docz links for page styling.

Resolution order when `mode: "auto"`:

1. `--theme <path>` (explicit CLI override)
2. `themes/default/dist/docz.tailwind.css` (monorepo build)
3. `third_party/tailwind/docz-theme-*/css/docz.tailwind.css` (vendored)
4. Built‑in `docz.default.css` (ships with Docz)

- **`mode`**: `"auto"` (use order above) or a fixed mode (e.g., `"vendored"` in the future).
- **`path`**: Absolute/relative path to a CSS file to force usage.
- **`prefer_vendored`**: Prefer vendored Tailwind over built‑in default if both exist.
- **`fallback`**: Built‑in theme to use if nothing else is found (currently `"default"`).

> Regardless of the theme, Docz **always** includes `docz.core.css` (reset + CSS tokens). Your `@style(mode:"global")` overrides are injected after the theme so they win.

---

## `tailwind` — Optional pro‑mode

Only relevant if you want to **build your own** Tailwind theme (utilities, plugins, safelists, etc.). Not required for the default Docz experience.

- **`enabled`**: If `true`, Docz expects you to have a Tailwind toolchain and will run a build step (if wired).
- **`config`**: Path to `tailwind.config.ts|js`.
- **`input`**: Entry CSS containing `@tailwind` directives.
- **`output`**: Path where your compiled CSS will be written (Docz will consume this file).
- **`postcss`**: Optional PostCSS config if you want plugins like autoprefixer, nesting, cssnano.

If `enabled` is `false`, Docz simply **consumes** prebuilt CSS (monorepo/vendored/built‑in).

---

## `csp` — Content Security Policy (Security)

**What is CSP?**  
CSP (**Content Security Policy**) is a powerful HTTP header that tells the browser **which sources of content are allowed**. It protects against many classes of cross‑site scripting (XSS). If an attacker injects inline JS, the browser will refuse to execute it unless it matches the policy.

- **`enabled`**: Whether Docz sends CSP headers (preview) and embeds an equivalent `<meta http-equiv="Content-Security-Policy" …>` in exported HTML.
- **`script_src`**: Allowed script sources. `"'self'"` ≈ only scripts served from your own origin. This **blocks inline scripts and `eval`**, which is why Docz serves JS as external files with SRI.
- **`style_src`**: Allowed style sources. `"'self'"` allows linked stylesheets. Docz injects your `@style(mode:"global")` overrides as a stylesheet from self, so it remains compliant.
- **`img_src`**: Allowed image sources (e.g., `["'self'","data:"]` to allow embedded data URLs).
- **`object_src`**: Disallow old plug‑in containers like `<object>`/`<embed>` with `["'none'"]`.
- **`worker_src`**: Allow web workers from self (future‑proofing for WASM isolation).
- **`base_uri`**: Disallow changing the document base with `<base>` (mitigates some phishing tricks).
- **`frame_ancestors`**: Which sites may embed your pages in iframes. `["'none'"]` prevents clickjacking.

**Bottom line:** With CSP on, your Docz pages only load **known, hashed** assets from your site and reject unexpected inline code by default.

---

## `wasm` — WebAssembly surface

- **`enabled`**: Enables the WASM execution surface (Docz will still serve `.wasm` with the correct MIME either way).
- **`timeout_ms`**: Fetch/instantiate timeout for WASM modules to prevent hangs.

---

## `logging` — Verbosity & format

- **`level`**: `"error" | "warn" | "info" | "debug"`.
- **`json`**: If `true`, structured JSON logs (CI‑friendly). Otherwise, human‑readable.

---

## How these pieces fit together

- **Zero‑config delight**: Out of the box, Docz serves `docz.core.css` + a theme (vendored or built‑in), under CSP, with ETags and strict MIME types.
- **Power on demand**: Flip `tailwind.enabled` and run a build if you want utility classes/plugins—Docz will simply consume your compiled CSS (hashed with SRI).
- **Deterministic & secure**: Content‑hashed assets, SRI‑verified links, CSP to block inline/eval, correct MIME for `.wasm`, optional compression, and proper caching—all controlled here.

---

### Quick reference (recommended defaults)

```json
{
  "preview": { "host": "127.0.0.1", "port": 0, "open": true, "strict_mime": true },
  "build":   { "hash_assets": true, "integrity": "sha256", "katex": "server" },
  "theme":   { "mode": "auto", "prefer_vendored": true, "fallback": "default" },
  "csp":     { "enabled": true, "script_src": ["'self'"], "style_src": ["'self'"] }
}
```
