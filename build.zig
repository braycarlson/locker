const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const win32 = builder.dependency("zigwin32", .{});
    const win32Module = win32.module("win32");

    const resources = builder.addSystemCommand(&[_][]const u8{
        "windres",
        "-i",
        "locker.rc",
        "-o",
        "locker.res",
        "--input-format=rc",
        "--output-format=coff",
    });

    const exeModule = builder.createModule(.{
        .root_source_file = builder.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exeModule.addImport("win32", win32Module);

    const exe = builder.addExecutable(.{
        .name = "locker",
        .root_module = exeModule,
    });

    exe.addObjectFile(builder.path("locker.res"));
    exe.step.dependOn(&resources.step);

    exe.linkLibC();
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("shell32");

    exe.subsystem = .Windows;

    builder.installArtifact(exe);

    const testStep = builder.step("test", "Run unit tests");

    const testModule = builder.createModule(.{
        .root_source_file = builder.path("src/harness.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unitTests = builder.addTest(.{
        .root_module = testModule,
    });

    const runTests = builder.addRunArtifact(unitTests);
    testStep.dependOn(&runTests.step);
}
