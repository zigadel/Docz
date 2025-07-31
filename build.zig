const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ✅ CLI module with target + optimize
    const cli_module = b.createModule(.{
        .root_source_file = b.path("core/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ✅ Executable (Docz CLI)
    const exe = b.addExecutable(.{
        .name = "docz",
        .root_module = cli_module,
    });

    b.installArtifact(exe);

    // ✅ Tests aggregate everything via root.zig
    const test_module = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = test_module,
    });

    // ✅ Build steps
    const run_step = b.step("run", "Run the Docz CLI");
    run_step.dependOn(&b.addRunArtifact(exe).step);

    const test_step = b.step("test", "Run all inline tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
