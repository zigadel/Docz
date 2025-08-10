const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Optional verbosity for tests
    const verbose_tests =
        b.option(bool, "verbose-tests", "Print debug logs in tests") orelse false;

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
    // 🖥 CLI module (we'll attach converter imports before creating the exe)
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
    //   Each converter imports AST via @import("docz")
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

    // Expose converters to the CLI (so main.zig can @import them)
    cli_root_module.addImport("html_import", html_import_mod);
    cli_root_module.addImport("html_export", html_export_mod);
    cli_root_module.addImport("md_import", md_import_mod);
    cli_root_module.addImport("md_export", md_export_mod);
    cli_root_module.addImport("latex_import", latex_import_mod);
    cli_root_module.addImport("latex_export", latex_export_mod);

    // ─────────────────────────────────────────────
    // 🖥 CLI executable (after adding imports)
    // ─────────────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "docz",
        .root_module = cli_root_module,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the Docz CLI");
    run_step.dependOn(&run_cmd.step);

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
    // 🧪 Integration tests
    // ─────────────────────────────────────────────
    const integration_module = b.createModule(.{
        .root_source_file = b.path("tests/test_all_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_module.addImport("docz", docz_module);
    integration_module.addOptions("build_options", build_opts);

    // Provide internal converters to integration tests
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
    const e2e_step = b.step("test-e2e", "Run end-to-end tests");
    e2e_step.dependOn(&e2e_run.step);
    e2e_step.dependOn(b.getInstallStep());

    // ─────────────────────────────────────────────
    // 🔁 Aggregate
    // ─────────────────────────────────────────────
    const all_tests = b.step("test-all", "Run unit + integration + e2e tests");
    all_tests.dependOn(unit_step);
    all_tests.dependOn(integration_step);
    all_tests.dependOn(e2e_step);
}
