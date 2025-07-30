# Contributing to Docz

Welcome to the future of documentation.  
**Docz is not just a tool—it is a foundation for the next era of knowledge.**

Where Markdown (`.md`) gave us simplicity, Docz (`.dcz`) gives us **structure, security, and extensibility**—a documentation engine built for humans and machines, for timelessness and clarity.

Thank you for considering contributing to this mission.

---

## 1. The Why: What Is Docz?

Docz is a **Zig-based documentation engine** that:
- Parses `.dcz` files into a structured AST.
- Executes embedded logic in a **secure WASM sandbox**.
- Outputs formats for any renderer—**including but not limited to Quartz**, a separate knowledge platform that uses `.dcz` as its core.

**Important:**  
- **Docz ≠ Quartz.** Quartz is a consumer of Docz, much like VSCode consumes TypeScript.  
- Docz stands alone as a complete CLI-driven documentation system with optional GUI components and a plugin ecosystem.

---

## 2. Principles of Contribution

Before writing a line of code, understand what makes Docz different:
- **Deterministic by Design:** Every build must be reproducible and cryptographically verifiable.
- **Secure by Default:** WASM sandboxing is non-negotiable.
- **Extensible through Plugins:** Keep the core minimal. Everything else is modular.
- **Readable, Maintainable, Timeless:** Code and docs must age well.

If your contribution aligns with these principles, you’re in the right place.

---

## 3. Quick Setup (With Context)

### Why Zig?
Zig provides:
- Safety without garbage collection.
- Direct WASM compilation.
- Deterministic builds.

### Prerequisites:
- Install Zig ≥ 0.13.0 → [https://ziglang.org/download](https://ziglang.org/download)

### Install & Build:
```bash
git clone https://github.com/zigadel/docz.git
cd docz
zig build
```

### Run Tests:
```bash
zig build test
```

---

## 4. Development Workflow

We use a branching strategy that prioritizes **stability and clarity**:
- `main` → Stable releases only.
- `dev` → Integration branch for new features.
- `feature/<name>` → Isolated work in progress.

### Why this matters:
- `main` must always be production-ready.
- Code review ensures **architectural integrity** and **security compliance**.

For full details, see [WORKFLOW.md](../docs/WORKFLOW.md).

---

## 5. Code & Style Conventions

Consistency is not cosmetic—it’s structural integrity:
- **Zig:** Use `zig fmt` and follow [STYLE_GUIDE.md](../docs/STYLE_GUIDE.md).
- **Docz Syntax (`.dcz`):**
    - Explicit directives (`@heading(level=1)`) instead of ambiguous symbols.
    - Parameterized styles over inline hacks.
    - Always close block directives with `@end`.

Why? Because structure > shortcuts. Readable code and docs are future-proof.

---

## 6. Testing as Integrity

Docz treats tests as part of the code—not an afterthought:
- Inline tests inside Zig files.
- 100% coverage goal for parser, CLI, and core logic.
- Why inline? Because tests should live **where the logic lives**.

Example:
```zig
test "parse heading directive" {
    const result = try parseDocz("@heading(level=2) Title @end");
    try expectEqual(result[0].node_type, NodeType.Heading);
}
```

Run all tests:
```bash
zig build test
```

---

## 7. Plugins Are the Future

Docz is a **plugin-first ecosystem**:
- Plugins extend functionality without inflating the core.
- All major features—math, diagrams, simulation—live as plugins.
- Every plugin:
    - Declares hooks (`onRegister`, `onParse`, `onRender`).
    - Has a `plugin.zon` manifest.
    - Includes inline tests.

Start here: [PLUGIN_GUIDE.md](../docs/PLUGIN_GUIDE.md).

---

## 8. Security & Responsibility

Docz is built for **trust in reproducible builds**:
- All dependencies must be hash-verified.
- WASM execution is sandboxed.
- No unchecked file or network I/O.

If you add code that touches security boundaries, **please document and justify every line**.

---

## 9. The Contributor’s Ethos

Contributing to Docz is not just about features—it’s about shaping an **infrastructure of understanding** that will outlast trends.

Every `.dcz` document you enable, every directive you define, every security guarantee you enforce makes Docz:
- **The future default** for documentation.
- A platform that elevates clarity, logic, and trust.

Welcome aboard. We're creating the new de facto for storing, searching, and presenting knowledge!

---

### Related Docs
- [ROADMAP.md](../docs/ROADMAP.md) – Strategic phases.
- [WORKFLOW.md](../docs/WORKFLOW.md) – Branching, CI/CD, PR standards.
- [STYLE_GUIDE.md](../docs/STYLE_GUIDE.md) – Code and syntax rules.
