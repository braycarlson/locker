const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const nimble = builder.dependency("nimble", .{
        .target = target,
        .optimize = optimize,
    });

    const wisp = builder.dependency("wisp", .{
        .target = target,
        .optimize = optimize,
    });

    const win32 = builder.dependency("zigwin32", .{});

    const nimble_module = nimble.module("nimble");
    const win32_module = win32.module("win32");
    const wisp_module = wisp.module("wisp");

    const resource = builder.addSystemCommand(&[_][]const u8{
        "windres",
        "-i",
        "locker.rc",
        "-o",
        "locker.res",
        "--input-format=rc",
        "--output-format=coff",
    });

    const exe_module = builder.createModule(.{
        .root_source_file = builder.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_module.addImport("nimble", nimble_module);
    exe_module.addImport("win32", win32_module);
    exe_module.addImport("wisp", wisp_module);

    const exe = builder.addExecutable(.{
        .name = "locker",
        .root_module = exe_module,
    });

    exe.addObjectFile(builder.path("locker.res"));
    exe.step.dependOn(&resource.step);

    exe.linkLibC();
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("shell32");

    exe.subsystem = .Windows;

    builder.installArtifact(exe);

    const test_step = builder.step("test", "Run unit tests");

    const test_module = builder.createModule(.{
        .root_source_file = builder.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    test_module.addImport("nimble", nimble_module);
    test_module.addImport("win32", win32_module);
    test_module.addImport("wisp", wisp_module);

    const unit_test = builder.addTest(.{
        .root_module = test_module,
    });

    const run_test = builder.addRunArtifact(unit_test);
    test_step.dependOn(&run_test.step);
}
