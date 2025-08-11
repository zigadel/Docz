const std = @import("std");
const builtin = @import("builtin");

// Link platform-specific networking deps based on the *artifact's* target.
// Works for native and cross builds.
fn linkPlatformNetDeps(artifact: *std.Build.Step.Compile) void {
    const rt = artifact.root_module.resolved_target orelse return;
    if (rt.result.os.tag == .windows) {
        // std.net/std.http on Windows requires Winsock
        artifact.linkSystemLibrary("ws2_32");
    }
    // Other OSes: nothing extra needed.
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Optional verbosity for tests
    const verbose_tests = b.option(bool, "verbose-tests", "Print debug logs in tests") orelse false;

    const build_opts = b.addOptions();
    build_opts.addOption(bool, "verbose_tests", verbose_tests);

    // ─────────────────────────────────────────────
    // 📦 Public module: docz (root.zig)
    // ─────────────────────────────────────────────
    const docz_module = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });
    docz_module.addOptions("build_options", build_opts);

    // ─────────────────────────────────────────────
    // 🖥 CLI module (attach converter imports before creating the exe)
    // ─────────────────────────────────────────────
    const cli_root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_root_module.addImport("docz", docz_module);
    cli_root_module.addOptions("build_options", build_opts);

    // ─────────────────────────────────────────────
    // 🔒 Internal converter modules (not exported via root.zig)
    // ─────────────────────────────────────────────
    const html_import_mod = b.createModule(.{
        .root_source_file = b.path("src/convert/html/import.zig"),
        .target = target,
        .optimize = optimize,
    });
    html_import_mod.addOptions("build_options", build_opts);
    html_import_mod.addImport("docz", docz_module);

    const html_export_mod = b.createModule(.{
        .root_source_file = b.path("src/convert/html/export.zig"),
        .target = target,
        .optimize = optimize,
    });
    html_export_mod.addOptions("build_options", build_opts);
    html_export_mod.addImport("docz", docz_module);

    const md_import_mod = b.createModule(.{
        .root_source_file = b.path("src/convert/markdown/import.zig"),
        .target = target,
        .optimize = optimize,
    });
    md_import_mod.addOptions("build_options", build_opts);
    md_import_mod.addImport("docz", docz_module);

    const md_export_mod = b.createModule(.{
        .root_source_file = b.path("src/convert/markdown/export.zig"),
        .target = target,
        .optimize = optimize,
    });
    md_export_mod.addOptions("build_options", build_opts);
    md_export_mod.addImport("docz", docz_module);

    const latex_import_mod = b.createModule(.{
        .root_source_file = b.path("src/convert/latex/import.zig"),
        .target = target,
        .optimize = optimize,
    });
    latex_import_mod.addOptions("build_options", build_opts);
    latex_import_mod.addImport("docz", docz_module);

    const latex_export_mod = b.createModule(.{
        .root_source_file = b.path("src/convert/latex/export.zig"),
        .target = target,
        .optimize = optimize,
    });
    latex_export_mod.addOptions("build_options", build_opts);
    latex_export_mod.addImport("docz", docz_module);

    // Expose converters to the CLI
    cli_root_module.addImport("html_import", html_import_mod);
    cli_root_module.addImport("html_export", html_export_mod);
    cli_root_module.addImport("md_import", md_import_mod);
    cli_root_module.addImport("md_export", md_export_mod);
    cli_root_module.addImport("latex_import", latex_import_mod);
    cli_root_module.addImport("latex_export", latex_export_mod);

    // ─────────────────────────────────────────────
    // 🖥 CLI executable
    // ─────────────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "docz",
        .root_module = cli_root_module,
    });
    // Link Winsock on Windows automatically
    linkPlatformNetDeps(exe);

    // Normal install (zig build install)
    b.installArtifact(exe);

    // Names (OS-aware)
    const exe_name = if (builtin.os.tag == .windows) "docz.exe" else "docz";
    const e2e_name = if (builtin.os.tag == .windows) "docz-e2e.exe" else "docz-e2e";

    // Install a separate e2e launcher so tests never lock the main binary
    const e2e_install = b.addInstallArtifact(exe, .{
        .dest_sub_path = e2e_name,
    });

    // Relative + absolute paths (helpful for tests)
    const docz_rel = b.fmt("zig-out/bin/{s}", .{exe_name});
    const e2e_rel = b.fmt("zig-out/bin/{s}", .{e2e_name});
    const docz_abs = b.getInstallPath(.bin, exe_name);
    const e2e_abs = b.getInstallPath(.bin, e2e_name);

    build_opts.addOption([]const u8, "docz_relpath", docz_rel);
    build_opts.addOption([]const u8, "e2e_relpath", e2e_rel);
    build_opts.addOption([]const u8, "docz_abspath", docz_abs);
    build_opts.addOption([]const u8, "e2e_abspath", e2e_abs);

    // Convenience run step (general)
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the Docz CLI");
    run_step.dependOn(&run_cmd.step);

    // Preview convenience: `zig build preview -- <args>`
    const prev = b.addRunArtifact(exe);
    prev.addArg("preview");
    if (b.args) |args| prev.addArgs(args);
    const prev_step = b.step("preview", "Run the web preview server");
    prev_step.dependOn(&prev.step);

    // ─────────────────────────────────────────────
    // 🧪 Unit tests (docz + each internal converter)
    // ─────────────────────────────────────────────
    const unit_tests = b.addTest(.{ .root_module = docz_module });
    const unit_run = b.addRunArtifact(unit_tests);

    const html_import_unit = b.addTest(.{ .root_module = html_import_mod });
    const html_import_unit_run = b.addRunArtifact(html_import_unit);

    const html_export_unit = b.addTest(.{ .root_module = html_export_mod });
    const html_export_unit_run = b.addRunArtifact(html_export_unit);

    const md_import_unit = b.addTest(.{ .root_module = md_import_mod });
    const md_import_unit_run = b.addRunArtifact(md_import_unit);

    const md_export_unit = b.addTest(.{ .root_module = md_export_mod });
    const md_export_unit_run = b.addRunArtifact(md_export_unit);

    const latex_import_unit = b.addTest(.{ .root_module = latex_import_mod });
    const latex_import_unit_run = b.addRunArtifact(latex_import_unit);

    const latex_export_unit = b.addTest(.{ .root_module = latex_export_mod });
    const latex_export_unit_run = b.addRunArtifact(latex_export_unit);

    const unit_step = b.step("test", "Run unit tests");
    unit_step.dependOn(&unit_run.step);
    unit_step.dependOn(&html_import_unit_run.step);
    unit_step.dependOn(&html_export_unit_run.step);
    unit_step.dependOn(&md_import_unit_run.step);
    unit_step.dependOn(&md_export_unit_run.step);
    unit_step.dependOn(&latex_import_unit_run.step);
    unit_step.dependOn(&latex_export_unit_run.step);

    // ─────────────────────────────────────────────
    // 🧪 CLI unit tests (each CLI file is its own module-under-test)
    // ─────────────────────────────────────────────
    const cli_common_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_common_mod.addOptions("build_options", build_opts);
    cli_common_mod.addImport("docz", docz_module);

    const cli_convert_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/convert.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_convert_mod.addOptions("build_options", build_opts);
    cli_convert_mod.addImport("docz", docz_module);
    cli_convert_mod.addImport("html_import", html_import_mod);
    cli_convert_mod.addImport("html_export", html_export_mod);
    cli_convert_mod.addImport("md_import", md_import_mod);
    cli_convert_mod.addImport("md_export", md_export_mod);
    cli_convert_mod.addImport("latex_import", latex_import_mod);
    cli_convert_mod.addImport("latex_export", latex_export_mod);

    const cli_build_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/build_cmd.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_build_mod.addOptions("build_options", build_opts);
    cli_build_mod.addImport("docz", docz_module);

    const cli_preview_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/preview.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_preview_mod.addOptions("build_options", build_opts);
    cli_preview_mod.addImport("docz", docz_module);

    const cli_enable_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/enable_wasm.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_enable_mod.addOptions("build_options", build_opts);
    cli_enable_mod.addImport("docz", docz_module);

    const cli_common_unit = b.addTest(.{ .root_module = cli_common_mod });
    const cli_convert_unit = b.addTest(.{ .root_module = cli_convert_mod });
    const cli_build_unit = b.addTest(.{ .root_module = cli_build_mod });
    const cli_preview_unit = b.addTest(.{ .root_module = cli_preview_mod });
    const cli_enable_unit = b.addTest(.{ .root_module = cli_enable_mod });

    const cli_common_run = b.addRunArtifact(cli_common_unit);
    const cli_convert_run = b.addRunArtifact(cli_convert_unit);
    const cli_build_run = b.addRunArtifact(cli_build_unit);
    const cli_preview_run = b.addRunArtifact(cli_preview_unit);
    const cli_enable_run = b.addRunArtifact(cli_enable_unit);

    const cli_unit_step = b.step("test-cli", "Run CLI unit tests");
    cli_unit_step.dependOn(&cli_common_run.step);
    cli_unit_step.dependOn(&cli_convert_run.step);
    cli_unit_step.dependOn(&cli_build_run.step);
    cli_unit_step.dependOn(&cli_preview_run.step);
    cli_unit_step.dependOn(&cli_enable_run.step);

    // ─────────────────────────────────────────────
    // 🧪 Integration tests
    // ─────────────────────────────────────────────
    const integration_module = b.createModule(.{
        .root_source_file = b.path("tests/test_all_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_module.addImport("docz", docz_module);
    integration_module.addOptions("build_options", build_opts);
    integration_module.addImport("html_import", html_import_mod);
    integration_module.addImport("html_export", html_export_mod);
    integration_module.addImport("md_import", md_import_mod);
    integration_module.addImport("md_export", md_export_mod);
    integration_module.addImport("latex_import", latex_import_mod);
    integration_module.addImport("latex_export", latex_export_mod);

    const integration_tests = b.addTest(.{ .root_module = integration_module });
    const integration_run = b.addRunArtifact(integration_tests);
    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&integration_run.step);

    // ─────────────────────────────────────────────
    // 🧪 End-to-end tests
    // ─────────────────────────────────────────────
    const e2e_module = b.createModule(.{
        .root_source_file = b.path("tests/test_all_e2e.zig"),
        .target = target,
        .optimize = optimize,
    });
    e2e_module.addImport("docz", docz_module);
    e2e_module.addOptions("build_options", build_opts);

    const e2e_tests = b.addTest(.{ .root_module = e2e_module });
    const e2e_run = b.addRunArtifact(e2e_tests);

    // Give tests an ABSOLUTE path to the e2e launcher and ensure it exists first.
    e2e_run.setEnvironmentVariable("DOCZ_BIN", e2e_abs);
    e2e_run.step.dependOn(&e2e_install.step);

    const e2e_step = b.step("test-e2e", "Run end-to-end tests");
    e2e_step.dependOn(&e2e_run.step);

    // ─────────────────────────────────────────────
    // 🔁 Aggregate
    // ─────────────────────────────────────────────
    const all_tests = b.step("test-all", "Run unit + integration + e2e tests");
    all_tests.dependOn(unit_step);
    all_tests.dependOn(integration_step);
    all_tests.dependOn(e2e_step);
    all_tests.dependOn(cli_unit_step);
}
