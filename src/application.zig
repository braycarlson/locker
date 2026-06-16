const std = @import("std");

const arc = @import("arc");
const nimble = @import("nimble");
const win32 = @import("win32").everything;
const wisp = @import("wisp");

const Config = @import("config.zig").Config;
const ShortcutKind = @import("config.zig").ShortcutKind;
const constant = @import("constant.zig");
const Dispatcher = @import("handler.zig").Dispatcher;
const EventHandler = @import("handler.zig").EventHandler;
const IconManager = @import("icon.zig").IconManager;
const Logger = arc.Logger;
const MenuManager = @import("menu.zig").MenuManager;
const NotificationManager = @import("notification.zig").NotificationManager;
const Remap = @import("remap.zig").Remap;
const SettingsManager = @import("settings.zig").SettingsManager;
const State = @import("state.zig").State;

const App = wisp.App;
const Key = nimble.Key;
const Response = nimble.Response;
const Keyboard = nimble.Keyboard(.{});
const Mouse = nimble.Mouse(.{});

var instance: std.atomic.Value(?*Application) = std.atomic.Value(?*Application).init(null);

const dispatcher = Dispatcher{
    .on_config_reload = dispatch_config_reload,
    .on_exit = dispatch_exit,
    .on_init = dispatch_init,
    .on_lock = dispatch_lock,
    .on_menu_show = dispatch_menu_show,
    .on_open_settings = dispatch_open_settings,
    .on_shutdown = dispatch_shutdown,
    .on_timer_tick = dispatch_timer_tick,
    .on_toggle_keyboard = dispatch_toggle_keyboard,
    .on_toggle_mouse = dispatch_toggle_mouse,
    .on_toggle_state = dispatch_toggle_state,
    .on_unlock = dispatch_unlock,
};

pub const Application = struct {
    app: App,
    configuration: Config,
    handler: EventHandler,
    icon: IconManager,
    is_keyboard_locked: bool,
    is_mouse_locked: bool,
    keyboard: Keyboard,
    logger: ?*Logger,
    menu: MenuManager,
    mouse: Mouse,
    notification: NotificationManager,
    remap: Remap,
    settings: SettingsManager,
    state: State,

    pub fn init(self: *Application, io: std.Io, logger: ?*Logger) void {
        const configuration = Config.load(io);

        self.* = Application{
            .app = undefined,
            .configuration = configuration,
            .handler = undefined,
            .icon = undefined,
            .is_keyboard_locked = configuration.is_keyboard_locked,
            .is_mouse_locked = configuration.is_mouse_locked,
            .keyboard = Keyboard.init(),
            .logger = logger,
            .menu = undefined,
            .mouse = Mouse.init(),
            .notification = undefined,
            .remap = undefined,
            .settings = undefined,
            .state = .unlocked,
        };

        self.app.init(.{
            .name = "Locker",
            .tooltip = "Peripheral Locker",
            .initial_state = "unlocked",
        });

        _ = self.app.configure();
    }

    pub fn configure(self: *Application) !void {
        self.icon = IconManager.init(&self.app);
        self.icon.configure();

        self.menu = MenuManager.init(&self.app);

        self.notification = NotificationManager.init(
            &self.app,
            &self.icon,
            self.configuration.show_notification,
        );

        self.settings = SettingsManager.init(&self.configuration, self.logger);

        self.remap = Remap.init(&self.configuration, self.logger);

        self.keyboard.set_key_callback(remap_callback, self);

        self.handler = EventHandler.init(&self.app, &dispatcher);

        try self.register_triggers();

        self.log("Application is ready");
    }

    pub fn deinit(self: *Application) void {
        self.log("Shutting down");

        instance.store(null, .seq_cst);

        self.settings.deinit();
        self.keyboard.deinit();
        self.mouse.deinit();
        self.app.deinit();
        self.configuration.deinit();
    }

    pub fn run(self: *Application) void {
        instance.store(self, .seq_cst);

        self.configure() catch |err| {
            self.log_error("Failed to configure application", err);
            return;
        };

        self.handler.register();

        self.app.run() catch |err| {
            self.log_error("Failed to run application", err);
        };
    }

    fn lock(self: *Application) void {
        self.set_state(.locked, "trigger activated");
    }

    fn unlock(self: *Application) void {
        self.set_state(.unlocked, "trigger activated");
    }

    fn post_message(self: *Application, message: u32) void {
        std.debug.assert(message != 0);

        const handle = self.app.get_hwnd() orelse return;

        _ = win32.PostMessageW(handle, message, 0, 0);
    }

    fn log(self: *Application, message: []const u8) void {
        std.debug.assert(message.len > 0);

        if (self.logger) |logger| {
            logger.info(message, &.{}, @src());
        }
    }

    fn log_error(self: *Application, message: []const u8, err: anyerror) void {
        std.debug.assert(message.len > 0);

        if (self.logger) |logger| {
            logger.@"error"(message, &.{arc.err_from(err)}, @src());
        }
    }

    fn log_state(self: *Application, value: State, reason: []const u8) void {
        std.debug.assert(reason.len > 0);

        if (self.logger) |logger| {
            const message = if (value.is_locked()) "Peripherals locked" else "Peripherals unlocked";

            logger.info(message, &.{arc.string("reason", reason)}, @src());
        }
    }

    fn on_config_reload(self: *Application) void {
        if (!self.settings.reload()) {
            return;
        }

        self.remap = Remap.init(&self.configuration, self.logger);
        self.is_keyboard_locked = self.configuration.is_keyboard_locked;
        self.is_mouse_locked = self.configuration.is_mouse_locked;
        self.notification.set_enabled(self.configuration.show_notification);
    }

    fn on_exit(self: *Application) void {
        self.log("Exiting");
        self.app.quit();
    }

    fn on_init(self: *Application) void {
        self.keyboard.start() catch {
            self.log("Unable to start keyboard hook");
        };

        self.mouse.start() catch {
            self.log("Unable to start mouse hook");
        };

        _ = self.app.get_timer().start(constant.Timer.rehook_id, constant.Timer.rehook_interval_ms) catch null;

        self.settings.watch(on_config_file_changed);
    }

    fn on_menu_show(self: *Application) void {
        self.menu.build(self.state, self.is_keyboard_locked, self.is_mouse_locked);
    }

    fn on_open_settings(self: *Application) void {
        self.settings.open();
    }

    fn on_shutdown(self: *Application) void {
        self.keyboard.deinit();
        self.mouse.deinit();
    }

    fn on_timer_tick(self: *Application, timer_id: u32) void {
        if (timer_id == constant.Timer.rehook_id) {
            self.refresh_hooks();
        }
    }

    fn on_toggle_keyboard(self: *Application) void {
        self.set_keyboard_locked(!self.is_keyboard_locked);
    }

    fn on_toggle_mouse(self: *Application) void {
        self.set_mouse_locked(!self.is_mouse_locked);
    }

    fn on_toggle_state(self: *Application) void {
        self.toggle_state("selected from menu");
    }

    fn refresh_hooks(self: *Application) void {
        if (!self.keyboard.is_running()) {
            self.keyboard.start() catch {};
        }

        if (!self.mouse.is_running()) {
            self.mouse.start() catch {};
        }
    }

    fn register_triggers(self: *Application) !void {
        switch (self.configuration.lock_shortcut) {
            .combination => |combination| {
                _ = try self.keyboard.registry.register(
                    combination.value,
                    combination.modifier_set,
                    lock_bind_wrapper,
                    self,
                    .{},
                );
            },
            .sequence => |sequence| {
                _ = try self.keyboard.sequence(sequence.to_slice())
                    .on(self, lock_sequence_callback);
            },
        }

        switch (self.configuration.unlock_shortcut) {
            .combination => |combination| {
                _ = try self.keyboard.registry.register(
                    combination.value,
                    combination.modifier_set,
                    unlock_bind_wrapper,
                    self,
                    .{ .block_exempt = true },
                );
            },
            .sequence => |sequence| {
                _ = try self.keyboard.sequence(sequence.to_slice())
                    .block_exempt()
                    .on(self, unlock_sequence_callback);
            },
        }
    }

    fn set_keyboard_locked(self: *Application, value: bool) void {
        self.is_keyboard_locked = value;

        const message = if (value) "Keyboard blocking enabled" else "Keyboard blocking disabled";
        self.log(message);
    }

    fn set_mouse_locked(self: *Application, value: bool) void {
        self.is_mouse_locked = value;

        const message = if (value) "Mouse blocking enabled" else "Mouse blocking disabled";
        self.log(message);
    }

    fn set_state(self: *Application, value: State, reason: []const u8) void {
        std.debug.assert(reason.len > 0);

        self.state = value;

        if (value.is_locked()) {
            if (self.is_keyboard_locked) {
                self.keyboard.set_blocked(true);
            }

            if (self.is_mouse_locked) {
                self.mouse.set_blocked(true);
            }
        } else {
            self.keyboard.set_blocked(false);
            self.mouse.set_blocked(false);
        }

        self.icon.update(value);
        self.log_state(value, reason);
        self.notification.show(value);
    }

    fn toggle_state(self: *Application, reason: []const u8) void {
        std.debug.assert(reason.len > 0);
        self.set_state(self.state.toggle(), reason);
    }
};

fn current() ?*Application {
    return instance.load(.seq_cst);
}

fn dispatch_config_reload() void {
    const app = current() orelse return;
    app.on_config_reload();
}

fn dispatch_exit() void {
    const app = current() orelse return;
    app.on_exit();
}

fn dispatch_init() void {
    const app = current() orelse return;
    app.on_init();
}

fn dispatch_lock() void {
    const app = current() orelse return;
    app.lock();
}

fn dispatch_menu_show() void {
    const app = current() orelse return;
    app.on_menu_show();
}

fn dispatch_open_settings() void {
    const app = current() orelse return;
    app.on_open_settings();
}

fn dispatch_shutdown() void {
    const app = current() orelse return;
    app.on_shutdown();
}

fn dispatch_timer_tick(timer_id: u32) void {
    const app = current() orelse return;
    app.on_timer_tick(timer_id);
}

fn dispatch_toggle_keyboard() void {
    const app = current() orelse return;
    app.on_toggle_keyboard();
}

fn dispatch_toggle_mouse() void {
    const app = current() orelse return;
    app.on_toggle_mouse();
}

fn dispatch_toggle_state() void {
    const app = current() orelse return;
    app.on_toggle_state();
}

fn dispatch_unlock() void {
    const app = current() orelse return;
    app.unlock();
}

fn lock_bind_wrapper(context: *anyopaque, key: *const Key) Response {
    _ = key;

    const self: *Application = @ptrCast(@alignCast(context));
    self.post_message(constant.wm_lock);

    return .consume;
}

fn lock_sequence_callback(self: *Application) void {
    self.post_message(constant.wm_lock);
}

fn on_config_file_changed() void {
    const app = current() orelse return;
    app.post_message(constant.wm_config_reload);
}

fn remap_callback(context: *anyopaque, value: u8, is_down: bool, extra: u64) ?u32 {
    const self: *Application = @ptrCast(@alignCast(context));
    return self.remap.process(value, is_down, extra);
}

fn unlock_bind_wrapper(context: *anyopaque, key: *const Key) Response {
    _ = key;

    const self: *Application = @ptrCast(@alignCast(context));
    self.post_message(constant.wm_unlock);

    return .consume;
}

fn unlock_sequence_callback(self: *Application) void {
    self.post_message(constant.wm_unlock);
}
