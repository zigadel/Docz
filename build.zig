const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ─────────────────────────────────────────────
    // Executable: Docz CLI
    // ─────────────────────────────────────────────
    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "docz",
        .root_module = cli_module,
    });

    b.installArtifact(exe);

    // ─────────────────────────────────────────────
    // Unit Tests via root.zig
    // ─────────────────────────────────────────────
    const unit_module = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_module = unit_module,
    });

    const test_step = b.step("test", "Run all inline unit tests");
    test_step.dependOn(&unit_tests.step);

    // ─────────────────────────────────────────────
    // Integration Tests via tests/test_all_integration.zig
    // ─────────────────────────────────────────────
    const integration_module = b.createModule(.{
        .root_source_file = b.path("tests/test_all_integration.zig"),
        .target = target,
        .optimize = optimize,
    });

    const integration_tests = b.addTest(.{
        .root_module = integration_module,
    });

    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&integration_tests.step);

    // ─────────────────────────────────────────────
    // End-to-End Tests via tests/test_all_e2e.zig
    // ─────────────────────────────────────────────
    const e2e_module = b.createModule(.{
        .root_source_file = b.path("tests/test_all_e2e.zig"),
        .target = target,
        .optimize = optimize,
    });

    const e2e_tests = b.addTest(.{
        .root_module = e2e_module,
    });

    const e2e_step = b.step("test-e2e", "Run end-to-end tests");
    e2e_step.dependOn(&e2e_tests.step);

    // ─────────────────────────────────────────────
    // Run all tests together
    // ─────────────────────────────────────────────
    const all_tests = b.step("test-all", "Run unit + integration + e2e tests");
    all_tests.dependOn(&unit_tests.step);
    all_tests.dependOn(&integration_tests.step);
    all_tests.dependOn(&e2e_tests.step);

    // ─────────────────────────────────────────────
    // Run the CLI
    // ─────────────────────────────────────────────
    const run_step = b.step("run", "Run the Docz CLI");
    run_step.dependOn(&b.addRunArtifact(exe).step);
}
