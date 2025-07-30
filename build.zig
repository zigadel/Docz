const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the root module and specify the main Zig source file
    const root_module = b.addModule("docz", .{
        .root_source_file = b.path("core/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create executable using the root module
    const exe = b.addExecutable(.{
        .name = "docz",
        .root_module = root_module,
    });

    // Install CLI binary into zig-out/bin
    b.installArtifact(exe);

    // Add convenient run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the docz CLI");
    run_step.dependOn(&run_cmd.step);

    // Add test module for inline Zig tests
    const test_module = b.addModule("docz_tests", .{
        .root_source_file = b.path("core/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&tests.step);
}
