# ROADMAP.md – The Strategic Blueprint for Docz

Docz is not just another documentation tool—it is **the foundation for a new era of structured knowledge**.  
Where Markdown gave us simplicity, Docz introduces **semantic rigor, security, and extensibility** as first-class principles.  

This roadmap is not a checklist—it is an **architectural manifesto**, designed to guide contributors toward building a system that will remain relevant for decades.

---

## 1. Why This Roadmap Exists

Current documentation ecosystems fail because:
- **Markdown is weak**: It lacks structure, semantic meaning, and security guarantees.
- **Execution is unsafe**: Embedded code runs without isolation or trust validation.
- **Extensibility is chaotic**: Plugins exist as ad-hoc hacks, with no universal framework.

Docz changes this by:
- Defining `.dcz` as a **structured, declarative documentation format**.
- Building a **deterministic, Zig-based core**.
- Providing **secure WASM execution** for embedded logic.
- Designing a **plugin-first ecosystem** that scales without bloating the core.

This roadmap explains **how we build Docz into the universal standard for documentation**.

---

## 2. Guiding Principles

- **Deterministic by Design**: Every build is reproducible and cryptographically verifiable.
- **Secure by Default**: WASM sandboxing for all executable code.
- **Minimal Core, Infinite Extension**: The core handles parsing, validation, and rendering; everything else is modular.
- **Timeless Architecture**: Docz is designed to last beyond 2025, using first principles, not trends.
- **Quartz Independence**: Docz is self-sufficient. Quartz is an optional consumer, not a dependency.

---

## 3. Vision Architecture (Conceptual Flow)

```
.dcz Source
    ↓ Parsing & Validation (Zig)
Structured AST
    ↓ Renderers
HTML / PDF / JSON / WASM
    ↓ Consumers
Quartz / Minimal GUI / Custom Pipelines
    ↓ Extensions
Plugins, Themes, Exporters
```

Key insights:
- **AST as the single source of truth** → Enables infinite rendering possibilities.
- **Plugins as architectural nodes** → Add power without breaking stability.
- **Output-agnostic design** → Docz works anywhere, from CLI to web to native.

---

## 4. Strategic Objectives

1. Establish `.dcz` as the **universal structured documentation format**.
2. Build a **deterministic Zig-based core** with secure parsing and rendering.
3. Implement **WASM sandboxing** for safe embedded execution.
4. Create a **plugin-first architecture** for extensibility.
5. Deliver an **optional GUI layer** for non-Quartz users.
6. Define **testing, security, and style standards** for every contributor.

---

## 5. Multi-Phase Development Blueprint

Each phase is a **layer in the system architecture**, not just a timeline.

---

### **Phase 1: Core Foundation (Current Priority)**
**Goal:** Make Docz operational as a standalone engine.
- ✅ Parser:
    - Tokenize `.dcz` syntax → AST.
    - Enforce directive integrity and strict validation.
- ✅ Renderer:
    - Convert AST → HTML with theming hooks.
- ✅ CLI:
    - Commands: `docz build`, `docz preview`.
- ✅ Testing:
    - Inline Zig tests for every module.
- **Why This Matters:** A strong foundation ensures future modularity.

**Deliverable:**  
A deterministic binary that converts `.dcz` → HTML with complete test coverage.

---

### **Phase 2: Plugin & Theme Ecosystem**
**Goal:** Unlock modularity and user innovation.
- ✅ Plugin Loader:
    - Validate manifests (`plugin.zon`).
    - Register hooks (`onRegister`, `onRender`).
- ✅ Core Plugins:
    - `plugin-math` → LaTeX rendering.
    - `plugin-zeno` → Simulation support.
- ✅ Theme Engine:
    - Declarative `.dczstyle` files for styling.
- **Why This Matters:** Prevent core bloat while enabling ecosystem growth.

---

### **Phase 3: Developer Experience**
**Goal:** Lower friction for adoption and contribution.
- ✅ VSCode Extension:
    - Syntax highlighting and directive hints.
- ✅ Web Preview:
    - Live `.dcz` rendering in the browser.
- ✅ Minimal GUI:
    - Optional standalone renderer for GUI users.
- **Why This Matters:** Accessibility accelerates adoption without coupling to Quartz.

---

### **Phase 4: Advanced Capabilities**
**Goal:** Secure execution, marketplace, and long-term trust.
- ✅ WASM Sandbox:
    - Isolate and verify embedded logic.
- ✅ Plugin Marketplace:
    - Verified plugins with cryptographic signatures.
- ✅ Quartz API Integration:
    - Docz outputs seamlessly integrated into Quartz IDE.
- **Why This Matters:** Secure, composable, and adaptable for the future.

---

## 6. Cross-Phase Initiatives

- **Security First**: Hash-verify all dependencies, sandbox all code.
- **Test Discipline**: Inline tests enforced by CI on every PR.
- **Documentation as Code**: Update `.dcz` samples alongside every feature.

---

## 7. Risk & Resilience Strategy

| Risk                    | Mitigation                                    |
|------------------------ |-----------------------------------------------|
| Zig evolution          | Pin to stable release, adapt CI early.       |
| Plugin vulnerabilities | Mandatory hash verification + sandboxing.    |
| Ecosystem drift        | Centralized registry for verified plugins.   |
| Scope creep            | Enforce roadmap principles in PR reviews.    |

---

## 8. Horizon: Stretch Goals

- **AI-Assisted Plugins**: Summarization, diagramming, and intelligent linting.
- **Universal Export Pipeline**: PDF, EPUB, and fully interactive web outputs.
- **Parallel Rendering**: Multi-threaded Zig pipelines for large `.dcz` projects.
- **Self-Hosted Ecosystem**: Native `.dcz` rendering on Zigadel’s future GitHub alternative.

---

## 9. The Roadmap as a Social Contract

This roadmap is not just a technical document—it is a **declaration of intent**:
- Every contributor helps shape **a universal standard for structured knowledge**.
- Every commit moves Docz closer to **clarity, reproducibility, and trust**.
- Every plugin extends this mission without compromising integrity.

You are not just writing code—you are **building the future default for documentation**.

---

### Related Docs
- [WORKFLOW.md](./WORKFLOW.md)
- [CONTRIBUTING.md](../.github/CONTRIBUTING.md)
- [STYLE_GUIDE.md](./STYLE_GUIDE.md)
- [PLUGIN_GUIDE.md](./PLUGIN_GUIDE.md)
- [DEPENDENCIES.md](./DEPENDENCIES.md)

---

**Last Updated:** {Insert Date}
