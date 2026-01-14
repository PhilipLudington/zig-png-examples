const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // PNG library dependency
    const png_dep = b.dependency("png", .{
        .target = target,
        .optimize = optimize,
    });

    // SDL3 library dependency
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zig-png-examples",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "png", .module = png_dep.module("png") },
            },
        }),
    });

    // Link SDL3
    exe.linkLibrary(sdl_dep.artifact("SDL3"));

    b.installArtifact(exe);

    // Run step for main app
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the PNG viewer");
    run_step.dependOn(&run_cmd.step);

    // Browser executable
    const browser = b.addExecutable(.{
        .name = "png-browser",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/browser.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "png", .module = png_dep.module("png") },
            },
        }),
    });
    browser.linkLibrary(sdl_dep.artifact("SDL3"));
    b.installArtifact(browser);

    // Run step for browser
    const run_browser_cmd = b.addRunArtifact(browser);
    run_browser_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_browser_cmd.addArgs(args);
    }

    const run_browser_step = b.step("run-browser", "Run the PNG folder browser");
    run_browser_step.dependOn(&run_browser_cmd.step);

    // Test step
    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "png", .module = png_dep.module("png") },
            },
        }),
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
