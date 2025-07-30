# Docz Dependency Management Guide

This guide explains how **Docz** manages dependencies for reproducibility, modularity, and security using Zig-inspired manifests. It combines concepts from both dependency structure and ecosystem philosophy.

---

## 1. Why Dependency Management Matters

- **Reproducibility**: Same build everywhere.
- **Security**: Verified hashes, no arbitrary code.
- **Modularity**: Core stays minimal; features are plugin-driven.

Without proper dependency management:
- Builds become fragile.
- Security risks increase.
- Teams waste time troubleshooting environments.

Docz solves this by:
- Using `docz.zig.zon` as a manifest.
- Pinning versions in `docz.zig.lock`.
- Enforcing SHA-256 hash verification.

---

## 2. Core Philosophy

- **Zero unnecessary dependencies**:
    - Core = Pure Zig.
    - Plugins & themes = Optional.
- Predictable builds, minimal attack surface, maximum performance.

---

## 3. Dependency Layers

| Layer        | Purpose                                  |
|------------- |------------------------------------------|
| **Core**     | Parser, AST, Renderer, CLI.             |
| **Plugins**  | Adds features like Math, Plots, Graphs. |
| **Themes**   | Visual styles (academic, minimal, dark).|
| **Exporters**| PDF, ePub, HTML outputs.                |

Quartz (UI) is **not a dependency** of Docz. It uses Docz as a library or CLI.

---

## 4. Core Dependencies

- **Language**: Zig (≥ 0.13.0 recommended latest).
- **Core Components**:
    - `parser`: Converts `.dcz` → AST.
    - `renderer`: HTML, PDF.
    - `cli`: Command-line interface.
    - `wasm-core`: Secure execution of embedded Zig code.

Install Zig:
```bash
curl -fsSL https://ziglang.org/builds/zig-linux-x86_64-latest.tar.xz | tar -xJ
zig version
```

Build Docz:
```bash
zig build
zig build test
```

---

## 5. Manifest: `docz.zig.zon`

Defines project metadata, plugins, and themes:

```zon
.{
    .name = "docz-project",
    .version = "0.1.0",

    .plugins = .{
        .plugin-zeno = .{
            .url = "https://github.com/zigadel/plugin-zeno/archive/main.tar.gz",
            .hash = "1220abcd1234ef5678abcd1234ef5678"
        }
    },

    .themes = .{
        .academic = .{
            .url = "https://github.com/zigadel/docz-themes/archive/main.tar.gz",
            .hash = "1220efgh5678ijklmnop"
        }
    }
}
```

---

## 6. Lockfile: `docz.zig.lock`

Ensures deterministic builds by pinning exact versions:
```zon
.{
    .plugins = .{
        .plugin-zeno = .{
            .version = "1.0.3",
            .hash = "1220abcd1234ef5678abcd1234ef5678"
        }
    }
}
```

Always commit the lockfile to version control.

---

## 7. CLI Commands for Dependencies

### Install all from manifest:
```bash
qz install
```

### Add a plugin:
```bash
qz add plugin-zeno --url https://github.com/zigadel/plugin-zeno/archive/main.tar.gz --hash 1220abcd1234
```

### Remove a plugin:
```bash
qz remove plugin-zeno
```

### Update all:
```bash
qz update
```

---

## 8. Directory Structure

```
project-root/
    docz.zig.zon        # Manifest file
    docz.zig.lock       # Lockfile
    .docz-packages/     # Installed plugins & themes
```

---

## 9. Example: Multi-Plugin Setup

```zon
.{
    .name = "enterprise-docz",
    .version = "1.2.0",

    .plugins = .{
        .plugin-zeno = .{ .url = "https://github.com/zigadel/plugin-zeno", .hash = "1220abcd1234" },
        .plugin-qdraw = .{ .url = "https://github.com/zigadel/plugin-qdraw", .hash = "1220efgh5678" },
        .plugin-python = .{ .url = "https://github.com/zigadel/plugin-python", .hash = "1220ijkl9012" }
    }
}
```

---

## 10. Themes Management

Themes define UI without altering content.

Example:
```bash
qz add theme-academic --url https://github.com/zigadel/docz-themes/archive/main.tar.gz --hash 1220mnop
```

Import theme:
```text
@import("themes/academic.dczstyle")
```

---

## 11. Best Practices

- Commit `docz.zig.lock`.
- Verify hashes for all dependencies.
- Avoid using `latest` tags.
- Regularly audit installed plugins:
```bash
qz audit
```

---

## 12. Troubleshooting

- **Install fails** → Check internet and hashes.
- **Hash mismatch** → Recompute SHA-256 and update manifest.
- **Lockfile out of sync** → `qz sync`.

---

## 13. Security Checklist

- Validate all hashes.
- Use only trusted plugin sources.
- Review plugin code.

---

## 14. Workflow Diagram

```text
.dcz Files
     ↓
docz.zig.zon (Manifest)
     ↓ qz install
.docz-packages/ (Plugins)
     ↓
Quartz Runtime → WASM Execution
```

---

## 15. FAQs

**Q: Can I host plugins privately?**
A: Yes. Use HTTPS or Git URLs in manifest.

**Q: Does Docz support semantic versioning?**
A: Yes. Pin versions explicitly.

**Q: Can I use plugins without hashes?**
A: No. Hash verification is mandatory for security.

---

## 16. Related Files

- `PLUGIN_GUIDE.md`: Writing plugins.
- `DEVELOPMENT.md`: Build system overview.
