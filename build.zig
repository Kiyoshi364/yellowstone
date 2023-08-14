const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Create simulation Module
    const sim_module = b.createModule(.{
        .source_file = .{ .path = "lib_sim/simulation.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "yellowstone",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("lib_sim", sim_module);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing.
    const exe_tests_lib_sim = b.addTest(.{
        .root_source_file = .{ .path = "lib_sim/simulation.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_lib_sim_step = b.step("test_lib_sim", "Run unit tests for lib_sim");
    test_lib_sim_step.dependOn(&b.addRunArtifact(exe_tests_lib_sim).step);

    const exe_tests_main = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_tests_main.addModule("lib_sim", sim_module);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(exe_tests_main).step);
    test_step.dependOn(test_lib_sim_step);

    // Creates a step for docs.
    const main_docs = b.addInstallDirectory(.{
        .source_dir = exe_tests_main.getEmittedDocs(),
        .install_dir = .{ .custom = ".." },
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Build docs");
    docs_step.dependOn(&main_docs.step);
}
