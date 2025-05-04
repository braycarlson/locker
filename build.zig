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

    const hook = builder.addSharedLibrary(.{
        .name = "hook",
        .root_source_file = builder.path("src/hook.zig"),
        .target = target,
        .optimize = optimize,
    });

    hook.root_module.addImport("win32", win32_mod);

    hook.linkLibC();
    hook.linkSystemLibrary("user32");
    builder.installArtifact(hook);

    const exe = builder.addExecutable(.{
        .name = "locker",
        .root_source_file = builder.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("win32", win32_mod);

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
