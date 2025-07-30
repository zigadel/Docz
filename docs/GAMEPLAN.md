# GAMEPLAN.md – The Tactical Execution Blueprint for Docz

This document is the **bridge between strategy (ROADMAP) and execution (WORKFLOW)**.  
If ROADMAP is **why** and **what**, GAMEPLAN is **how**. It defines **immediate priorities, phase-based objectives, tactical workflows, and daily actionable steps** to build Docz into the universal standard for structured documentation.

---

## 1. Mission Statement

Docz is not just software. It is **infrastructure for structured knowledge**.  
This game plan ensures that:
- Every feature aligns with the **core principles**: determinism, security, modularity, and timelessness.
- Execution is **systematic**, reducing technical debt and enforcing architectural integrity.
- Every contributor can onboard quickly and **know what to do next**.

---

## 2. Operating Principles

Before touching a line of code, understand these:
- **Security by Default:** All contributions assume adversarial conditions. Sandbox everything.
- **Determinism First:** If it isn’t reproducible, it isn’t acceptable.
- **Minimal Core, Infinite Extension:** Keep the core lean; push complexity into plugins.
- **Automation Everywhere:** Every process must be enforceable by CI/CD.
- **Fail Closed:** All error states default to safe behavior.

---

## 3. High-Level Structure of Work

Phases map to **architectural layers**:
- **Phase 1:** Core engine foundation (parser, AST, renderer, CLI).
- **Phase 2:** Plugin & theme ecosystem (modularity).
- **Phase 3:** Developer experience (editor tooling, previews).
- **Phase 4:** Advanced capabilities (sandboxing, marketplace, integrations).

**Execution Model:**  
- **Each phase closes security gaps before introducing complexity.**
- **Every feature merged must include inline tests, docs, and CI compliance.**

---

## 4. Current Repository Structure

```sh
docz/
    core/               # Parser, renderer, CLI
    plugins/            # Official plugins
    examples/           # Example .dcz files
    vscode-extension/   # VSCode tooling
    web-preview/        # Browser live preview
    docs/               # Internal execution docs
    .github/            # Workflows, PR templates
```

Future additions:
- `sandbox/` → WASM execution layer.
- `themes/` → Core theme packages.
- `marketplace/` → Plugin registry backend.

---

## 5. Immediate Tactical Priorities (Next 30 Days)

### ✅ Priority 1: Core Parser & AST
- Implement **full `.dcz` tokenization**.
- Build **AST node system with validation hooks**.
- Define **directive spec** in `docs/STYLE_GUIDE.md` and lock it.

### ✅ Priority 2: Renderer → HTML
- Implement baseline renderer:
    - AST → HTML mapping.
    - Support for headings, paragraphs, images, code blocks.
- Add **theme hook layer** for Phase 2 extensibility.

### ✅ Priority 3: CLI Commands
- `docz build` → Compile `.dcz` to HTML.
- `docz preview` → Local static server with hot reload.
- Implement structured error messages for invalid syntax.

### ✅ Priority 4: Inline Testing Framework
- Enforce **tests per module** with `zig build test`.
- Coverage target: **100% for parser and CLI**.

---

## 6. Phase-by-Phase Tactical Breakdown

### **Phase 1: Core Foundation (Parser + Renderer + CLI)**
**Goal:** A standalone engine that can parse `.dcz` → HTML deterministically.

#### Tasks:
- [ ] **Tokenizer** for all directives.
- [ ] **AST Node Struct** with type enums.
- [ ] Parser validation for:
    - Missing `@end` blocks.
    - Invalid key-value pairs.
- [ ] Renderer:
    - Base HTML output.
    - Add hooks for style injection.
- [ ] CLI:
    - Commands: `build`, `preview`.
    - Error reporting with contextual hints.
- [ ] CI:
    - Lint `.dcz` samples.
    - Build binaries for Linux/macOS/Windows.
- [ ] Write sample `.dcz` files for regression testing.

#### Deliverable:
- `zig build` produces **deterministic binary**.
- HTML output matches test snapshots.

---

### **Phase 2: Plugin & Theme Ecosystem**
**Goal:** Enable modular extensibility without bloating core.

#### Tasks:
- [ ] Define **plugin manifest schema** (`plugin.zon`).
- [ ] Implement plugin loader with:
    - Manifest validation.
    - Hook registration: `onRegister`, `onParse`, `onRender`.
- [ ] Create **core plugin examples**:
    - `plugin-math`: Render LaTeX.
    - `plugin-zeno`: Simulation embedding.
- [ ] Theme system:
    - Load `.dczstyle` files.
    - Merge theme config with renderer pipeline.
- [ ] Security:
    - Enforce **hash verification** for plugins.
    - Prepare for WASM sandbox enforcement.

#### Deliverable:
- `docz install plugin-name` functional.
- Theme import supported in `.dcz`.

---

### **Phase 3: Developer Experience**
**Goal:** Make Docz frictionless for daily use.

#### Tasks:
- [ ] VSCode Extension:
    - Syntax highlighting.
    - Autocomplete for directives.
- [ ] Web Preview:
    - Browser live reload.
    - Full AST inspection panel.
- [ ] Optional GUI for Docz:
    - Minimalist, cross-platform viewer.

---

### **Phase 4: Advanced Capabilities**
**Goal:** Harden Docz for production-grade usage.

#### Tasks:
- [ ] WASM Sandbox:
    - Secure execution for `@code` blocks.
- [ ] Plugin Marketplace:
    - Registry with signed manifests.
- [ ] Quartz API Integration:
    - Output Docz → Quartz seamlessly.

---

## 7. Security Workflows by Phase

- **Phase 1:** Validate `.dcz` syntax, lock directive spec.
- **Phase 2:** Hash verification for plugins.
- **Phase 3:** WASM sandbox prototype.
- **Phase 4:** Full sandbox enforcement + plugin marketplace verification.

---

## 8. Daily Development Workflow
1. Pull latest `dev` branch.
2. Create feature branch:
```bash
git checkout -b feature/<task-name>
```
3. Implement feature with **inline tests**.
4. Run:
```bash
zig build
zig build test
```
5. Commit with **Conventional Commits** format.
6. Push & open PR → Await review + CI green check.

---

## 9. CI/CD Enforcement
- Lint: `zig fmt`, `.dcz` lint.
- Tests: Inline Zig tests mandatory.
- Security: Hash check for dependencies.
- Release flow:
    - Tag `vX.Y.Z` → triggers artifact build and checksum generation.

---

## 10. Contributor Action Map (Who Does What)
- **Core Maintainers:** Parser, renderer, CLI.
- **Plugin Developers:** Create isolated, hash-verified extensions.
- **Security Auditors:** Validate sandbox + plugin registry integrity.
- **DX Team:** VSCode extension, preview UI, docs.

---

## 11. Next Steps for All Contributors
- Read: [ROADMAP.md](./ROADMAP.md), [STYLE_GUIDE.md](./STYLE_GUIDE.md), [WORKFLOW.md](./WORKFLOW.md).
- Clone, build, and run sample `.dcz` files.
- Start with **Phase 1 tasks** → Parser completeness is top priority.

---

### Related Docs
- [CONTRIBUTING.md](../.github/CONTRIBUTING.md)
- [ROADMAP.md](./ROADMAP.md)
- [WORKFLOW.md](./WORKFLOW.md)
- [STYLE_GUIDE.md](./STYLE_GUIDE.md)
- [PLUGIN_GUIDE.md](./PLUGIN_GUIDE.md)

---

**Last Updated:** {Insert Date}