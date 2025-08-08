const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ─────────────────────────────────────────────
    // 📦 Shared docz module (root.zig)
    // ─────────────────────────────────────────────
    const docz_module = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ─────────────────────────────────────────────
    // 🖥 CLI Executable: docz
    // ─────────────────────────────────────────────
    const cli_root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_root_module.addImport("docz", docz_module);

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
    // 🧪 Unit Tests (inline tests in root.zig tree)
    // ─────────────────────────────────────────────
    const unit_tests = b.addTest(.{
        .root_module = docz_module,
    });
    const unit_run = b.addRunArtifact(unit_tests);

    const unit_step = b.step("test", "Run unit tests");
    unit_step.dependOn(&unit_run.step);

    // ─────────────────────────────────────────────
    // 🧪 Integration Tests (tests/test_all_integration.zig)
    // ─────────────────────────────────────────────
    const integration_module = b.createModule(.{
        .root_source_file = b.path("tests/test_all_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_module.addImport("docz", docz_module);

    const integration_tests = b.addTest(.{
        .root_module = integration_module,
    });
    const integration_run = b.addRunArtifact(integration_tests);

    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&integration_run.step);

    // ─────────────────────────────────────────────
    // 🧪 End-to-End Tests (tests/test_all_e2e.zig)
    // ─────────────────────────────────────────────
    const e2e_module = b.createModule(.{
        .root_source_file = b.path("tests/test_all_e2e.zig"),
        .target = target,
        .optimize = optimize,
    });
    e2e_module.addImport("docz", docz_module);

    const e2e_tests = b.addTest(.{
        .root_module = e2e_module,
    });
    const e2e_run = b.addRunArtifact(e2e_tests);

    const e2e_step = b.step("test-e2e", "Run end-to-end tests");
    e2e_step.dependOn(&e2e_run.step);

    // ─────────────────────────────────────────────
    // 🔁 test-all: aggregate test step (runs all)
    // ─────────────────────────────────────────────
    const all_tests = b.step("test-all", "Run unit + integration + e2e tests");
    all_tests.dependOn(unit_step); // note: pass *Step directly
    all_tests.dependOn(integration_step);
    all_tests.dependOn(e2e_step);
}
