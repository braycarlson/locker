const std = @import("std");

const arc = @import("arc");
const nimble = @import("nimble");
const umbra = @import("umbra");

const Config = @import("config.zig").Config;
const icon = @import("icon.zig");
const menu = @import("menu.zig");
const Remap = @import("remap.zig").Remap;
const State = @import("state.zig").State;

const assert = std.debug.assert;

const App = umbra.App;
const CapacityError = nimble.remote.CapacityError;
const Client = nimble.remote.Client;
const Command = menu.Command;
const Custom = umbra.Event.Custom;
const Key = nimble.Key;
const Logger = arc.Logger;
const Pattern = Client.Pattern;
const PlatformError = nimble.remote.PlatformError;
const RequestError = nimble.remote.RequestError;
const Response = nimble.Response;
const Selection = umbra.Event.Selection;
const Tick = umbra.Event.Tick;

const RemoteError = CapacityError || PlatformError || RequestError;
const RunError = umbra.Error || RemoteError;

pub const Message = enum(u32) {
    config_reload = 1,
    lock = 2,
    rescue = 4,
    unlock = 3,
    _,
};

pub const TimerID = enum(u32) {
    rehook = 1,
    _,
};

const name = "Locker";
const rehook_interval_ms: u32 = 10 * 60 * 1000;
const title = "Peripheral Locker";

comptime {
    assert(name.len > 0);
    assert(rehook_interval_ms > 0);
    assert(title.len > 0);
}

pub const Application = struct {
    app: App,
    client: Client,
    configuration: Config,
    logger: ?*const Logger,
    peripherals: Client.Blocked,
    remap: Remap,
    state: State,
    watch: ?umbra.watcher.Watch,

    pub fn init(
        application: *Application,
        io: std.Io,
        logger: ?*const Logger,
    ) umbra.Error!void {
        application.* = .{
            .app = undefined,
            .client = .{},
            .configuration = undefined,
            .logger = logger,
            .peripherals = .{},
            .remap = undefined,
            .state = .unlocked,
            .watch = null,
        };

        application.configuration.init(io);

        application.configuration.load() catch |err| {
            application.log_configuration_error(
                "Unable to load the configuration, using the defaults",
                err,
            );
        };

        application.peripherals = application.configured_peripherals();
        application.remap = Remap.init(&application.configuration, &application.client, logger);

        try application.app.init(.{ .name = name, .tooltip = title });
        errdefer application.app.deinit();

        try icon.register(&application.app.icons);
        try icon.show(&application.app.icons, application.state);

        menu.fill(&application.app.menu, application.state, application.peripherals) catch {
            application.log("Unable to fill the menu");
        };

        assert(!application.app.is_running());
        assert(!application.state.is_locked());

        application.log("Application is ready");
    }

    pub fn deinit(application: *Application) void {
        application.log("Shutting down");

        if (application.watch) |handle| {
            umbra.watcher.unwatch(handle);

            application.watch = null;
        }

        application.client.disconnect();
        application.app.deinit();

        assert(!application.app.is_running());
        assert(!application.client.is_connected());
    }

    pub fn run(application: *Application) RunError!void {
        try application.app.bus.attach(Application, application);

        application.client.connect() catch |err| {
            application.log_error("Unable to connect to the input service", err);

            return err;
        };

        application.client.set_release_callback(Application, application, on_rescue_release);

        application.install_remap_filter() catch |err| {
            application.log_error("Unable to install the remap filter", err);
        };

        application.register_triggers() catch |err| {
            application.log_error("Unable to register the lock triggers", err);

            return err;
        };

        application.push_block_state();

        application.app.run() catch |err| {
            application.log_error("Unable to run the application", err);

            return err;
        };
    }

    pub fn blocked(application: *const Application) Client.Blocked {
        if (!application.state.is_locked()) {
            return .{};
        }

        return application.peripherals;
    }

    pub fn on_app_init(application: *Application) void {
        const rehook = umbra.TimerSet.Timer{
            .id = @backingInt(TimerID.rehook),
            .interval_ms = rehook_interval_ms,
        };

        application.app.timers.start(rehook) catch {
            application.log("Unable to start the rehook timer");
        };

        application.watch_configuration();

        application.log("Initialized");
    }

    pub fn on_app_shutdown(application: *Application) void {
        application.log("Shutdown event received");

        application.app.timers.stop(@backingInt(TimerID.rehook)) catch {
            application.log("Unable to stop the rehook timer");

            return;
        };
    }

    pub fn on_custom(application: *Application, custom: Custom) void {
        switch (@as(Message, @fromBackingInt(custom.code))) {
            .lock => application.lock("trigger activated"),
            .unlock => application.unlock("trigger activated"),
            .config_reload => application.on_config_reload(),
            .rescue => application.on_rescue(),
            _ => {},
        }
    }

    pub fn on_menu_select(application: *Application, selection: Selection) void {
        switch (@as(Command, @fromBackingInt(selection.id))) {
            .toggle => application.toggle_state("selected from menu"),
            .toggle_keyboard => application.on_toggle_keyboard(),
            .toggle_mouse => application.on_toggle_mouse(),
            .setting => application.open_settings(),
            .exit => application.on_exit(),
            _ => {},
        }
    }

    pub fn on_menu_show(application: *Application) void {
        application.refresh_menu();
    }

    pub fn on_timer_tick(application: *Application, tick: Tick) void {
        switch (@as(TimerID, @fromBackingInt(tick.id))) {
            .rehook => application.refresh_hooks(),
            _ => {},
        }
    }

    fn configured_peripherals(application: *const Application) Client.Blocked {
        return .{
            .keyboard = application.configuration.is_keyboard_locked,
            .mouse = application.configuration.is_mouse_locked,
        };
    }

    fn install_remap_filter(application: *Application) RemoteError!void {
        const patterns = [_]Pattern{
            .{ .key = .super, .modifiers_match = .at_least },
            .{ .key = .super_left, .modifiers_match = .at_least },
            .{ .key = .super_right, .modifiers_match = .at_least },
            .{ .modifiers = .from(.{ .win = true }), .modifiers_match = .at_least },
        };

        try application.client.set_filter(&patterns, Application, application, on_remap_filter);
    }

    fn lock(application: *Application, reason: []const u8) void {
        assert(reason.len > 0);

        if (application.state.is_locked()) {
            return;
        }

        application.set_state(.locked, reason);
    }

    fn notify(application: *Application, value: State) void {
        if (!application.configuration.show_notification) {
            return;
        }

        const body = value.to_notification_body();

        application.app.notifier.send(.{ .body = body, .title = title }) catch {
            return;
        };
    }

    fn on_config_reload(application: *Application) void {
        application.configuration.reload() catch |err| {
            application.log_configuration_error("Rejected an invalid configuration", err);

            return;
        };

        application.peripherals = application.configured_peripherals();

        application.refresh_menu();
        application.log("Configuration reloaded");
    }

    fn on_exit(application: *Application) void {
        application.log("Exiting");
        application.app.quit();
    }

    fn on_rescue(application: *Application) void {
        application.log("Rescue released the input grab");
        application.unlock("rescue chord held");
    }

    fn on_toggle_keyboard(application: *Application) void {
        application.peripherals.keyboard = !application.peripherals.keyboard;

        const enabled = application.peripherals.keyboard;
        const message = if (enabled) "Keyboard blocking enabled" else "Keyboard blocking disabled";

        application.log(message);
    }

    fn on_toggle_mouse(application: *Application) void {
        application.peripherals.mouse = !application.peripherals.mouse;

        const enabled = application.peripherals.mouse;
        const message = if (enabled) "Mouse blocking enabled" else "Mouse blocking disabled";

        application.log(message);
    }

    fn open_settings(application: *Application) void {
        const path = application.configuration.get_path() orelse return;

        application.log("Opening settings file");

        umbra.shell.open(path) catch {
            application.log("Unable to open the settings file");

            return;
        };
    }

    fn push_block_state(application: *Application) void {
        application.client.set_blocked(application.blocked()) catch |err| {
            application.log_error("Unable to push the block state", err);
        };
    }

    fn refresh_hooks(application: *Application) void {
        if (application.client.is_connected()) {
            application.push_block_state();

            return;
        }

        application.log("Reconnecting to the input daemon");

        application.client.connect() catch |err| {
            application.log_error("Unable to reconnect to the input daemon", err);

            return;
        };

        application.client.set_release_callback(Application, application, on_rescue_release);

        application.install_remap_filter() catch |err| {
            application.log_error("Unable to reinstall the remap filter", err);
        };

        application.register_triggers() catch |err| {
            application.log_error("Unable to re-register the lock triggers", err);
        };

        application.push_block_state();
    }

    fn refresh_menu(application: *Application) void {
        menu.fill(&application.app.menu, application.state, application.peripherals) catch {
            application.log("Unable to fill the menu");
        };

        application.app.menu.build() catch {
            return;
        };
    }

    fn register_triggers(application: *Application) RemoteError!void {
        const client = &application.client;

        switch (application.configuration.lock_shortcut) {
            .combination => |combination| {
                _ = try client.bind_key(
                    combination.value,
                    combination.modifier_set,
                    .{ .consume = true },
                    Application,
                    application,
                    on_lock_trigger,
                );
            },
            .sequence => |sequence| {
                _ = try client.bind_sequence(
                    sequence.to_slice(),
                    .{ .consume = true },
                    Application,
                    application,
                    on_lock_trigger,
                );
            },
        }

        switch (application.configuration.unlock_shortcut) {
            .combination => |combination| {
                _ = try client.bind_key(
                    combination.value,
                    combination.modifier_set,
                    .{ .consume = true, .exempt = true },
                    Application,
                    application,
                    on_unlock_trigger,
                );
            },
            .sequence => |sequence| {
                _ = try client.bind_sequence(
                    sequence.to_slice(),
                    .{ .consume = true, .exempt = true },
                    Application,
                    application,
                    on_unlock_trigger,
                );
            },
        }
    }

    fn set_state(application: *Application, value: State, reason: []const u8) void {
        assert(reason.len > 0);

        application.state = value;

        application.push_block_state();

        icon.show(&application.app.icons, value) catch {
            application.log("Unable to show the tray icon");
        };

        application.refresh_menu();
        application.log_state(value, reason);
        application.notify(value);

        assert(application.state == value);
    }

    fn toggle_state(application: *Application, reason: []const u8) void {
        assert(reason.len > 0);

        if (application.state.is_locked()) {
            application.unlock(reason);

            return;
        }

        application.lock(reason);
    }

    fn unlock(application: *Application, reason: []const u8) void {
        assert(reason.len > 0);

        if (!application.state.is_locked()) {
            return;
        }

        application.set_state(.unlocked, reason);
    }

    fn watch_configuration(application: *Application) void {
        assert(application.watch == null);

        const path = application.configuration.get_path() orelse return;

        application.watch = umbra.watcher.watch(
            path,
            Application,
            application,
            on_config_file_changed,
        ) catch {
            application.log("Unable to watch the settings file");

            return;
        };
    }

    fn log(application: *Application, message: []const u8) void {
        assert(message.len > 0);

        if (application.logger) |logger| {
            logger.information(message, &.{}, &@src());
        }
    }

    fn log_configuration_error(application: *Application, message: []const u8, err: anyerror) void {
        assert(message.len > 0);

        const diagnostic = application.configuration.diagnostic orelse {
            application.log_error(message, err);

            return;
        };

        if (application.logger) |logger| {
            logger.err(
                message,
                &.{
                    .{ .key = "error", .value = .{ .string = @errorName(err) } },
                    .{ .key = "line", .value = .{ .unsigned = diagnostic.position.line } },
                    .{ .key = "column", .value = .{ .unsigned = diagnostic.position.column } },
                    .{ .key = "reason", .value = .{ .string = diagnostic.reason } },
                },
                &@src(),
            );
        }
    }

    fn log_error(application: *Application, message: []const u8, err: anyerror) void {
        assert(message.len > 0);

        if (application.logger) |logger| {
            logger.err(
                message,
                &.{.{ .key = "error", .value = .{ .string = @errorName(err) } }},
                &@src(),
            );
        }
    }

    fn log_state(application: *Application, value: State, reason: []const u8) void {
        assert(reason.len > 0);

        if (application.logger) |logger| {
            const message = if (value.is_locked()) "Peripherals locked" else "Peripherals unlocked";

            logger.information(
                message,
                &.{.{ .key = "reason", .value = .{ .string = reason } }},
                &@src(),
            );
        }
    }
};

fn on_config_file_changed(_: *Application) void {
    _ = umbra.loop.post(@backingInt(Message.config_reload));
}

fn on_lock_trigger(_: *Application, _: ?*const Key) void {
    _ = umbra.loop.post(@backingInt(Message.lock));
}

fn on_remap_filter(application: *Application, key: *const Key) Response {
    return application.remap.process(key) orelse .pass;
}

fn on_rescue_release(_: *Application) void {
    _ = umbra.loop.post(@backingInt(Message.rescue));
}

fn on_unlock_trigger(_: *Application, _: ?*const Key) void {
    _ = umbra.loop.post(@backingInt(Message.unlock));
}

const testing = std.testing;

test Application {
    nimble.mock.reset();

    var application: Application = undefined;

    try application.init(testing.io, null);
    defer application.deinit();

    try testing.expectEqual(State.unlocked, application.state);
    try testing.expect(!application.blocked().keyboard);

    application.on_custom(.{ .code = @backingInt(Message.lock) });

    try testing.expectEqual(State.locked, application.state);
    try testing.expect(application.blocked().keyboard);
    try testing.expect(!application.blocked().mouse);

    application.on_menu_select(.{ .checked = false, .id = @backingInt(Command.toggle) });

    try testing.expectEqual(State.unlocked, application.state);
    try testing.expect(!application.blocked().keyboard);
}
