const std = @import("std");

const assert = std.debug.assert;

const format_paths = [_][]const u8{ "build.zig", "src" };

const Steps = struct {
    check: *std.Build.Step,
    ci: *std.Build.Step,
    run: *std.Build.Step,
    test_all: *std.Build.Step,
    test_fake: *std.Build.Step,
    test_fmt: *std.Build.Step,
    test_unit: *std.Build.Step,
};

const Context = struct {
    builder: *std.Build,
    filters: []const []const u8,
    optimize: std.lang.Optimize,
    steps: Steps,
    target: std.Build.ResolvedTarget,
};

const assets = [_][]const u8{ "lock.rgba", "unlock.rgba" };

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const filters = builder.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &.{};

    const context = Context{
        .builder = builder,
        .filters = filters,
        .optimize = optimize,
        .steps = .{
            .check = builder.step("check", "Compile every artifact without running it"),
            .ci = builder.step("ci", "Run every check and test"),
            .run = builder.step("run", "Build and run the application"),
            .test_all = builder.step("test", "Run every test suite and the format check"),
            .test_fake = builder.step(
                "test:fake",
                "Run the end to end tests against the fake backends",
            ),
            .test_fmt = builder.step("test:fmt", "Check that every source file is formatted"),
            .test_unit = builder.step("test:unit", "Run the unit tests and the tidy check"),
        },
        .target = target,
    };

    add_executable(context);
    add_unit_tests(context);
    add_fake_tests(context);
    add_cross_check(context);
    add_format(context);

    builder.getInstallStep().dependOn(context.steps.check);
}

fn add_executable(context: Context) void {
    const builder = context.builder;
    const module = create_module(context, "src/main.zig");
    const exe = builder.addExecutable(.{ .name = "locker", .root_module = module });

    add_windows_resource(context, module, exe);

    builder.installArtifact(exe);

    const run = builder.addRunArtifact(exe);

    run.step.dependOn(builder.getInstallStep());

    context.steps.run.dependOn(&run.step);
    context.steps.check.dependOn(&exe.step);
}

fn add_unit_tests(context: Context) void {
    const builder = context.builder;
    const module = create_module(context, "src/unit_tests.zig");
    const unit = builder.addTest(.{ .root_module = module, .filters = context.filters });
    const run = builder.addRunArtifact(unit);

    run.has_side_effects = true;
    run.setCwd(builder.path("."));

    context.steps.test_unit.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
    context.steps.check.dependOn(&unit.step);
    context.steps.ci.dependOn(context.steps.test_unit);
}

fn add_fake_tests(context: Context) void {
    const builder = context.builder;
    const module = create_module(context, "src/scenario.zig");
    const fake = builder.addTest(.{ .root_module = module, .filters = context.filters });
    const run = builder.addRunArtifact(fake);

    context.steps.test_fake.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
    context.steps.check.dependOn(&fake.step);
    context.steps.ci.dependOn(context.steps.test_fake);
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

        const module = create_module(scoped, "src/main.zig");

        const exe = builder.addExecutable(.{
            .name = builder.fmt("locker-{s}", .{@tagName(query.os_tag.?)}),
            .root_module = module,
        });

        add_windows_resource(scoped, module, exe);

        context.steps.check.dependOn(&exe.step);
    }
}

fn add_format(context: Context) void {
    const builder = context.builder;
    const format = builder.addFmt(.{ .paths = builder.pathList(&format_paths), .check = true });

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

    exe.subsystem = .windows;

    const builder = context.builder;
    const resource = std.Build.Step.Run.create(builder, "zig rc locker.rc");

    resource.addFileArg2(.zig_exe, .{});

    resource.addArgs(&.{
        "rc",
        "/:auto-includes",
        "any",
        "/:output-format",
        "coff",
        "/:target",
        @tagName(context.target.result.cpu.arch),
        "--",
    });

    resource.addFileArg2(builder.path("locker.rc"), .{});
    resource.addFileInput(builder.path("assets/unlock.ico"));

    const object = resource.addOutputFileArg2("locker.obj", .{});

    module.addObjectFile(object);
}

fn create_module(context: Context, root: []const u8) *std.Build.Module {
    assert(std.mem.startsWith(u8, root, "src/"));
    assert(std.mem.endsWith(u8, root, ".zig"));

    const builder = context.builder;

    const arc = builder.dependency("arc", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const nimble = builder.dependency("nimble", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const toml = builder.dependency("toml", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const umbra = builder.dependency("umbra", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const module = builder.createModule(.{
        .root_source_file = builder.path(root),
        .target = context.target,
        .optimize = context.optimize,
    });

    module.addImport("arc", arc.module("arc"));
    module.addImport("nimble", nimble.module("nimble"));
    module.addImport("toml", toml.module("toml"));
    module.addImport("umbra", umbra.module("umbra"));

    for (assets) |asset| {
        module.addAnonymousImport(asset, .{
            .root_source_file = builder.path(builder.fmt("assets/{s}", .{asset})),
        });
    }

    return module;
}
