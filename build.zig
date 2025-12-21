const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const win32_pkg = builder.dependency("zigwin32", .{});
    const win32_mod = win32_pkg.module("win32");

    const resources = builder.addSystemCommand(&[_][]const u8{
        "windres",
        "-i",
        "locker.rc",
        "-o",
        "locker.res",
        "--input-format=rc",
        "--output-format=coff",
    });

    const hook_mod = builder.createModule(.{
        .root_source_file = builder.path("src/hook.zig"),
        .target = target,
        .optimize = optimize,
    });
    hook_mod.addImport("win32", win32_mod);

    const hook = builder.addLibrary(.{
        .name = "hook",
        .linkage = .dynamic,
        .root_module = hook_mod,
    });

    hook.linkLibC();
    hook.linkSystemLibrary("user32");
    builder.installArtifact(hook);

    const exe_mod = builder.createModule(.{
        .root_source_file = builder.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("win32", win32_mod);

    const exe = builder.addExecutable(.{
        .name = "locker",
        .root_module = exe_mod,
    });

    exe.addObjectFile(builder.path("locker.res"));
    exe.step.dependOn(&resources.step);

    exe.linkLibrary(hook);
    exe.linkLibC();
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("shell32");

    exe.subsystem = .Windows;

    builder.installArtifact(exe);
}
