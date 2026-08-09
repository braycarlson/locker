const std = @import("std");

const arc = @import("arc");
const nimble = @import("nimble");
const wisp = @import("wisp");

const Config = @import("config.zig").Config;
const constant = @import("constant.zig");
const EventHandlerType = @import("handler.zig").EventHandlerType;
const IconManager = @import("icon.zig").IconManager;
const InputThread = @import("input.zig").InputThread;
const MenuManager = @import("menu.zig").MenuManager;
const NotificationManager = @import("notification.zig").NotificationManager;
const Remap = @import("remap.zig").Remap;
const SettingsManager = @import("settings.zig").SettingsManager;
const State = @import("state.zig").State;

const assert = std.debug.assert;

const App = wisp.App;
const Key = nimble.Key;
const Keycode = nimble.Keycode;
const Logger = arc.Logger;
const modifier = nimble.modifier;
const Pattern = nimble.remote.Pattern;
const Response = nimble.Response;

pub const Error = error{
    InputUnavailable,
    RunFailed,
    SetupFailed,
};

pub const name = "Locker";

comptime {
    assert(name.len > 0);
}

pub const Application = struct {
    app: App,
    configuration: Config,
    icon: IconManager,
    input: InputThread,
    is_keyboard_locked: bool,
    is_mouse_locked: bool,
    logger: ?*Logger,
    menu: MenuManager,
    notification: NotificationManager,
    remap: Remap,
    settings: SettingsManager,
    state: State,

    pub fn init(application: *Application, io: std.Io, logger: ?*Logger) Error!void {
        const configuration = Config.load(io);

        application.* = Application{
            .app = undefined,
            .configuration = configuration,
            .icon = undefined,
            .input = InputThread.init(),
            .is_keyboard_locked = configuration.is_keyboard_locked,
            .is_mouse_locked = configuration.is_mouse_locked,
            .logger = logger,
            .menu = undefined,
            .notification = undefined,
            .remap = undefined,
            .settings = undefined,
            .state = .unlocked,
        };

        application.app.init(.{
            .name = name,
            .tooltip = "Peripheral Locker",
            .initial_state = "unlocked",
        }) catch {
            return Error.SetupFailed;
        };

        errdefer application.app.deinit();

        application.icon = IconManager.init(&application.app);
        application.menu = MenuManager.init(&application.app);

        application.notification = NotificationManager.init(
            &application.app,
            application.configuration.show_notification,
        );

        application.remap = Remap.init(
            &application.configuration,
            application.input.handle(),
            logger,
        );

        application.settings = SettingsManager.init(&application.configuration, logger);

        application.icon.configure() catch {
            return Error.SetupFailed;
        };

        application.menu.build(
            application.state,
            application.is_keyboard_locked,
            application.is_mouse_locked,
        );

        _ = application.app.configure();

        assert(!application.app.is_running());
        assert(!application.state.is_locked());

        application.log("Application is ready");
    }

    pub fn deinit(application: *Application) void {
        application.log("Shutting down");

        application.settings.deinit();
        application.input.deinit();
        application.app.deinit();
        application.configuration.deinit();

        assert(!application.app.is_running());
    }

    pub fn run(application: *Application) Error!void {
        EventHandlerType(Application).register(&application.app.bus, application);

        application.input.start() catch |err| {
            application.log_error("Unable to start the input hooks", err);

            return Error.InputUnavailable;
        };

        application.input.handle().set_release_callback(rescue_release_callback, application);

        application.install_remap_filter() catch |err| {
            application.log_error("Unable to install the remap filter", err);
        };

        application.register_triggers() catch |err| {
            application.log_error("Unable to register the lock triggers", err);

            return Error.InputUnavailable;
        };

        application.push_block_state();

        application.run_app() catch |err| {
            application.log_error("Unable to run the application", err);

            return Error.RunFailed;
        };
    }

    fn run_app(application: *Application) !void {
        return application.app.run();
    }

    pub fn on_custom(application: *Application, code: u32) void {
        switch (code) {
            constant.Message.lock => application.lock("trigger activated"),
            constant.Message.unlock => application.unlock("trigger activated"),
            constant.Message.config_reload => application.on_config_reload(),
            constant.Message.rescue => application.on_rescue(),
            else => {},
        }
    }

    pub fn on_icon_change(application: *Application, icon_name: []const u8) void {
        assert(icon_name.len > 0);

        const handle = application.app.icon.get(icon_name) orelse return;

        application.app.tray.set_icon(handle) catch {
            application.log("Unable to update the tray icon");

            return;
        };
    }

    pub fn on_init(application: *Application) void {
        _ = application.app.timer.start(
            constant.Timer.rehook_id,
            constant.Timer.rehook_interval_ms,
        ) catch {
            application.log("Unable to start the rehook timer");
        };

        application.settings.watch(on_config_file_changed, application);

        application.log("Initialized");
    }

    pub fn on_menu_select(application: *Application, id: u32) void {
        switch (id) {
            constant.Menu.toggle => application.toggle_state("selected from menu"),
            constant.Menu.toggle_keyboard => application.on_toggle_keyboard(),
            constant.Menu.toggle_mouse => application.on_toggle_mouse(),
            constant.Menu.setting => application.settings.open(),
            constant.Menu.exit => application.on_exit(),
            else => {},
        }
    }

    pub fn on_menu_show(application: *Application) void {
        application.menu.build(
            application.state,
            application.is_keyboard_locked,
            application.is_mouse_locked,
        );

        application.menu.push();
    }

    pub fn on_shutdown(application: *Application) void {
        application.log("Shutdown event received");

        application.app.timer.stop(constant.Timer.rehook_id) catch {
            application.log("Unable to stop the rehook timer");

            return;
        };
    }

    pub fn on_timer_tick(application: *Application, timer_id: u32) void {
        if (timer_id == constant.Timer.rehook_id) {
            application.refresh_hooks();
        }
    }

    fn lock(application: *Application, reason: []const u8) void {
        assert(reason.len > 0);

        if (application.state.is_locked()) {
            return;
        }

        application.set_state(.locked, reason);
    }

    fn unlock(application: *Application, reason: []const u8) void {
        assert(reason.len > 0);

        if (!application.state.is_locked()) {
            return;
        }

        application.set_state(.unlocked, reason);
    }

    fn on_rescue(application: *Application) void {
        application.log("Rescue released the input grab");
        application.unlock("rescue chord held");
    }

    fn on_config_reload(application: *Application) void {
        if (!application.settings.reload()) {
            return;
        }

        application.is_keyboard_locked = application.configuration.is_keyboard_locked;
        application.is_mouse_locked = application.configuration.is_mouse_locked;

        application.notification.set_enabled(application.configuration.show_notification);

        application.menu.build(
            application.state,
            application.is_keyboard_locked,
            application.is_mouse_locked,
        );

        application.menu.push();
        application.log("Configuration reloaded");
    }

    fn on_exit(application: *Application) void {
        application.log("Exiting");
        application.app.quit();
    }

    fn on_toggle_keyboard(application: *Application) void {
        application.set_keyboard_locked(!application.is_keyboard_locked);
    }

    fn on_toggle_mouse(application: *Application) void {
        application.set_mouse_locked(!application.is_mouse_locked);
    }

    fn refresh_hooks(application: *Application) void {
        if (application.input.is_running()) {
            return;
        }

        application.log("Reconnecting to the input daemon");

        application.input.start() catch |err| {
            application.log_error("Unable to reconnect to the input daemon", err);

            return;
        };

        application.input.handle().set_release_callback(rescue_release_callback, application);

        application.install_remap_filter() catch |err| {
            application.log_error("Unable to reinstall the remap filter", err);
        };

        application.register_triggers() catch |err| {
            application.log_error("Unable to re-register the lock triggers", err);
        };

        application.push_block_state();
    }

    fn register_triggers(application: *Application) !void {
        const client = application.input.handle();

        switch (application.configuration.lock_shortcut) {
            .combination => |combination| {
                _ = try client.bind_key(
                    combination.value,
                    combination.modifier_set,
                    .{ .consume = true },
                    on_lock_trigger,
                    application,
                );
            },
            .sequence => |sequence| {
                _ = try client.bind_sequence(
                    sequence.to_slice(),
                    .{ .consume = true },
                    on_lock_trigger,
                    application,
                );
            },
        }

        switch (application.configuration.unlock_shortcut) {
            .combination => |combination| {
                _ = try client.bind_key(
                    combination.value,
                    combination.modifier_set,
                    .{ .consume = true, .exempt = true },
                    on_unlock_trigger,
                    application,
                );
            },
            .sequence => |sequence| {
                _ = try client.bind_sequence(
                    sequence.to_slice(),
                    .{ .consume = true, .exempt = true },
                    on_unlock_trigger,
                    application,
                );
            },
        }
    }

    fn install_remap_filter(application: *Application) !void {
        const win = modifier.Set.from(.{ .win = true });

        const patterns = [_]Pattern{
            .{ .key = @intFromEnum(Keycode.super), .match_any_modifiers = 1 },
            .{ .key = @intFromEnum(Keycode.super_left), .match_any_modifiers = 1 },
            .{ .key = @intFromEnum(Keycode.super_right), .match_any_modifiers = 1 },
            .{
                .modifiers = @intCast(win.flags),
                .match_any_modifiers = 1,
                .match_any_key = 1,
            },
        };

        try application.input.handle().set_filter(&patterns, remap_filter_callback, application);
    }

    fn push_block_state(application: *Application) void {
        application.input.handle().set_blocked(
            application.keyboard_blocked(),
            application.mouse_blocked(),
        );
    }

    pub fn keyboard_blocked(application: *const Application) bool {
        return application.state.is_locked() and application.is_keyboard_locked;
    }

    pub fn mouse_blocked(application: *const Application) bool {
        return application.state.is_locked() and application.is_mouse_locked;
    }

    fn set_keyboard_locked(application: *Application, value: bool) void {
        application.is_keyboard_locked = value;

        const message = if (value) "Keyboard blocking enabled" else "Keyboard blocking disabled";

        application.log(message);
    }

    fn set_mouse_locked(application: *Application, value: bool) void {
        application.is_mouse_locked = value;

        const message = if (value) "Mouse blocking enabled" else "Mouse blocking disabled";

        application.log(message);
    }

    fn set_state(application: *Application, value: State, reason: []const u8) void {
        assert(reason.len > 0);

        application.state = value;

        application.push_block_state();

        application.icon.update(value);
        application.menu.build(value, application.is_keyboard_locked, application.is_mouse_locked);
        application.menu.push();
        application.log_state(value, reason);
        application.notification.show(value);

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

    fn log(application: *Application, message: []const u8) void {
        assert(message.len > 0);

        if (application.logger) |logger| {
            logger.info(message, &.{}, @src());
        }
    }

    fn log_error(application: *Application, message: []const u8, err: anyerror) void {
        assert(message.len > 0);

        if (application.logger) |logger| {
            logger.@"error"(message, &.{arc.err_from(err)}, @src());
        }
    }

    fn log_state(application: *Application, value: State, reason: []const u8) void {
        assert(reason.len > 0);

        if (application.logger) |logger| {
            const message = if (value.is_locked()) "Peripherals locked" else "Peripherals unlocked";

            logger.info(message, &.{arc.string("reason", reason)}, @src());
        }
    }
};

fn on_lock_trigger(_: ?*anyopaque, _: ?*const Key) void {
    _ = wisp.loop.post(constant.Message.lock);
}

fn on_unlock_trigger(_: ?*anyopaque, _: ?*const Key) void {
    _ = wisp.loop.post(constant.Message.unlock);
}

fn rescue_release_callback(_: ?*anyopaque) void {
    _ = wisp.loop.post(constant.Message.rescue);
}

fn on_config_file_changed(context: ?*anyopaque) void {
    assert(context != null);

    _ = wisp.loop.post(constant.Message.config_reload);
}

fn remap_filter_callback(context: ?*anyopaque, key: *const Key) Response {
    const pointer = context orelse return .pass;
    const self: *Application = @ptrCast(@alignCast(pointer));

    return self.remap.process(key) orelse .pass;
}
