# WORKFLOW.md – The Contributor’s Operations Playbook for Docz

Docz is not a typical software project—it is **knowledge infrastructure**.  
Our workflow is designed to ensure **security, clarity, and reproducibility**, so that every change you make strengthens the foundation of this ecosystem.

This is not just “how to work”—it explains **why these processes exist**.

---

## 1. Why Workflow Matters

A workflow is the **chain of trust** in a decentralized ecosystem.  
In a world where `.dcz` may replace `.md` as the default knowledge format, we must guarantee:
- Every build is deterministic.
- Every feature merges only after validation.
- Every plugin upholds the same integrity guarantees as the core.

By following this workflow, you help Docz remain **secure, scalable, and timeless**.

---

## 2. Branching Model: Stability Through Structure

We follow a **tiered branching strategy** for clarity and risk containment:

| Branch       | Purpose                                |
|------------- |----------------------------------------|
| `main`       | Production-ready stable releases.     |
| `dev`        | Integration branch for upcoming release.|
| `feature/*`  | Isolated branches for new work.       |

### Why this matters:
- **`main` is sacred**: Always green, always release-ready.
- **`dev` is staging**: Collects features after review.
- **`feature/*` is isolation**: Prevents unstable code from contaminating integration.

**Rules:**
- Start all work from `dev`.
- Merge to `dev` via Pull Request after review and CI success.
- Only merge `dev` → `main` during release, never directly.

---

## 3. Commit Standards: Semantics = Future-Proofing

We use **Conventional Commits** for a reason:
- Enables **automated changelogs**.
- Provides **machine-readable history**.
- Improves collaboration by signaling intent.

| Prefix        | Meaning                                |
|-------------- |---------------------------------------|
| `feat:`       | New feature.                         |
| `fix:`        | Bug fix.                             |
| `docs:`       | Documentation changes.               |
| `refactor:`   | Internal change without behavior shift.|
| `test:`       | Adding/updating tests.              |
| `ci:`         | CI/CD or pipeline adjustments.       |

**Example:**
```
feat(parser): add directive parsing for @math
```

---

## 4. Pull Request Workflow: Quality as a Gate

Pull Requests are **architectural checkpoints**, not bureaucracy.  
Before merging:
- ✅ All tests must pass (`zig build test`).
- ✅ Linting applied (`zig fmt`, `qz lint` for `.dcz`).
- ✅ Documentation updated for new/changed features.
- ✅ Security-sensitive code explicitly reviewed.

**Review Policy:**
- Minimum **one maintainer approval**.
- No self-merging without emergency review exception.

---

## 5. Testing Workflow: Integrity Over Convenience

Tests are **inline** within `.zig` files. Why?  
- Locality improves maintenance.
- Documentation and verification live together.

**Run tests:**
```bash
zig build test
```

**Coverage Goal:**  
- 100% for parser, CLI, and plugin hooks.
- Both positive and negative cases.
- Include **fuzz tests for parser resilience**.

Example:
```zig
test "parse heading directive" {
    const result = try parseDocz("@heading(level=2) Title @end");
    try expectEqual(result[0].node_type, NodeType.Heading);
}
```

---

## 6. CI/CD Philosophy: Determinism + Security

Our pipelines enforce **immutability and trust**:
- **On PR:**  
    - Build with Zig.
    - Run full test suite.
    - Validate `.dcz` examples.
- **On Release Tag:**  
    - Build reproducible binaries.
    - Generate signed checksums.

**Workflows:**
- `ci.yml` → Tests on every PR.
- `release.yml` → Builds multi-platform artifacts.
- `extension-publish.yml` → Publishes VSCode extension.

---

## 7. Plugin Contribution Flow: Controlled Extensibility

Plugins are the **lifeblood of Docz**, but they must respect our guarantees:
- Each plugin includes:
    - `plugin.zon` manifest.
    - Hooks (`onRegister`, `onParse`, `onRender`).
    - Inline tests for all logic.
- Plugins follow **the same linting, testing, and security rules** as core.

**Flow:**
- Scaffold under `plugins/plugin-name/`.
- Add manifest, code, and tests.
- Submit PR for registry approval.

Reference: [PLUGIN_GUIDE.md](../docs/PLUGIN_GUIDE.md).

---

## 8. Security in Workflow: Non-Negotiable Standards

- All dependencies **hash-verified**.
- No unchecked WASM execution—sandbox required.
- PRs modifying:
    - File I/O,
    - Networking,
    - WASM runtime  
  **must undergo security review**.

---

## 9. Your Role in the Chain of Integrity

Every commit you make either strengthens or weakens Docz.  
Ask yourself before merging:
- Does this change make Docz **more deterministic, more secure, and more extensible**?
- Will this still make sense **10 years from now**?

If yes → Merge. If no → Rethink.

---

### Related Docs
- [CONTRIBUTING.md](../.github/CONTRIBUTING.md)
- [ROADMAP.md](./ROADMAP.md)
- [STYLE_GUIDE.md](./STYLE_GUIDE.md)
- [PLUGIN_GUIDE.md](./PLUGIN_GUIDE.md)

---

**Last Updated:** {Insert Date}
