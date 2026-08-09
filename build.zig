const std = @import("std");

const Backend = enum {
    native,
    mock,
};

const format_paths = [_][]const u8{ "build.zig", "src" };

const Steps = struct {
    check: *std.Build.Step,
    ci: *std.Build.Step,
    run: *std.Build.Step,
    test_all: *std.Build.Step,
    test_fmt: *std.Build.Step,
    test_mock: *std.Build.Step,
    test_unit: *std.Build.Step,
};

const Context = struct {
    builder: *std.Build,
    optimize: std.builtin.OptimizeMode,
    steps: Steps,
    target: std.Build.ResolvedTarget,
};

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const context = Context{
        .builder = builder,
        .optimize = optimize,
        .steps = .{
            .check = builder.step("check", "Compile every artifact without running it"),
            .ci = builder.step("ci", "Formatting, compilation and every test suite"),
            .run = builder.step("run", "Build and run the application"),
            .test_all = builder.step("test", "Run every test suite and the formatting check"),
            .test_fmt = builder.step("test:fmt", "Check that every source file is formatted"),
            .test_mock = builder.step("test:mock", "Run the end to end tests against the mocks"),
            .test_unit = builder.step("test:unit", "Run the colocated unit tests and the tidy law"),
        },
        .target = target,
    };

    add_executable(context);
    add_unit_tests(context);
    add_mock_tests(context);
    add_cross_check(context);
    add_format(context);

    builder.getInstallStep().dependOn(context.steps.check);
}

fn add_executable(context: Context) void {
    const builder = context.builder;

    const module = create_module(context, .native);

    const exe = builder.addExecutable(.{
        .name = "locker",
        .root_module = module,
    });

    add_windows_resource(context, module, exe);

    builder.installArtifact(exe);

    const run = builder.addRunArtifact(exe);

    run.step.dependOn(builder.getInstallStep());

    context.steps.run.dependOn(&run.step);
    context.steps.check.dependOn(&exe.step);
}

fn add_unit_tests(context: Context) void {
    const builder = context.builder;

    const module = create_module_from(context, .native, "src/unit_tests.zig");

    const unit = builder.addTest(.{
        .root_module = module,
        .filters = builder.args orelse &.{},
    });

    const run = builder.addRunArtifact(unit);

    context.steps.test_unit.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
    context.steps.check.dependOn(&unit.step);
    context.steps.ci.dependOn(context.steps.test_unit);
}

fn add_mock_tests(context: Context) void {
    const builder = context.builder;

    const module = create_module_from(context, .mock, "src/scenario.zig");

    const unit = builder.addTest(.{
        .root_module = module,
        .filters = builder.args orelse &.{},
    });

    const run = builder.addRunArtifact(unit);

    context.steps.test_mock.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
    context.steps.check.dependOn(&unit.step);
    context.steps.ci.dependOn(context.steps.test_mock);
}

fn add_cross_check(context: Context) void {
    const builder = context.builder;

    const queries = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    };

    for (queries) |query| {
        const resolved = builder.resolveTargetQuery(query);

        var scoped = context;

        scoped.target = resolved;

        const module = create_module(scoped, .native);

        const exe = builder.addExecutable(.{
            .name = builder.fmt("locker-{s}", .{@tagName(query.os_tag.?)}),
            .root_module = module,
        });

        add_windows_resource(scoped, module, exe);

        context.steps.ci.dependOn(&exe.step);
    }
}

fn add_format(context: Context) void {
    const builder = context.builder;

    const format = builder.addFmt(.{
        .paths = &format_paths,
        .check = true,
    });

    context.steps.test_fmt.dependOn(&format.step);
    context.steps.test_all.dependOn(&format.step);
    context.steps.ci.dependOn(context.steps.test_fmt);
    context.steps.ci.dependOn(context.steps.check);
}

fn add_windows_resource(
    context: Context,
    module: *std.Build.Module,
    exe: *std.Build.Step.Compile,
) void {
    if (context.target.result.os.tag != .windows) {
        return;
    }

    exe.subsystem = .Windows;

    module.addWin32ResourceFile(.{ .file = context.builder.path("locker.rc") });
}

fn create_module(context: Context, backend: Backend) *std.Build.Module {
    const result = create_module_from(context, backend, "src/main.zig");

    return result;
}

fn create_module_from(
    context: Context,
    backend: Backend,
    root: []const u8,
) *std.Build.Module {
    const builder = context.builder;

    const arc = builder.dependency("arc", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const nimble = builder.dependency("nimble", .{
        .target = context.target,
        .optimize = context.optimize,
        .backend = backend,
    });

    const wisp = builder.dependency("wisp", .{
        .target = context.target,
        .optimize = context.optimize,
        .backend = backend,
    });

    const module = builder.createModule(.{
        .root_source_file = builder.path(root),
        .target = context.target,
        .optimize = context.optimize,
    });

    module.addImport("arc", arc.module("arc"));
    module.addImport("nimble", nimble.module("nimble"));
    module.addImport("wisp", wisp.module("wisp"));

    module.addAnonymousImport("lock.rgba", .{
        .root_source_file = builder.path("asset/lock.rgba"),
    });

    module.addAnonymousImport("unlock.rgba", .{
        .root_source_file = builder.path("asset/unlock.rgba"),
    });

    return module;
}
