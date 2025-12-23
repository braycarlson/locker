const std = @import("std");

const toolkit = @import("toolkit");
const w32 = @import("win32").everything;

const config = @import("config.zig");
const constant = @import("constant.zig");
const remap = @import("remap.zig");

const Config = config.Config;
const Logger = @import("logger.zig").Logger;
const RemapHandler = remap.Remap;

pub const State = enum {
    locked,
    unlocked,

    pub fn isLocked(self: State) bool {
        std.debug.assert(self == .locked or self == .unlocked);

        return self == .locked;
    }

    pub fn toggle(self: State) State {
        std.debug.assert(self == .locked or self == .unlocked);

        if (self == .locked) {
            return .unlocked;
        }

        return .locked;
    }
};

var instance: *Locker = undefined;

pub const Locker = struct {
    const queue_capacity: u32 = 16;

    allocator: std.mem.Allocator,
    cfg: Config,
    context_menu: toolkit.ui.Menu = undefined,
    is_keyboard_locked: bool = true,
    is_mouse_locked: bool = false,
    keyboard_hook: toolkit.input.Hook = .{},
    lock_sequence: ?[]const u8 = null,
    logger: *?Logger,
    modifier: toolkit.input.ModifierSet = .{},
    mouse_hook: toolkit.input.Hook = .{},
    rehook_timer: toolkit.os.Timer = undefined,
    remap_handler: RemapHandler,
    sequence: toolkit.input.Sequence(queue_capacity) = .{},
    show_notification: bool = true,
    state: State = .unlocked,
    tray: toolkit.ui.Tray = undefined,
    unlock_sequence: ?[]const u8 = null,
    watcher: toolkit.os.Watcher,
    window: toolkit.os.Window = undefined,

    icon: struct {
        lock: toolkit.ui.Icon = .{},
        unlock: toolkit.ui.Icon = .{},
    } = .{},

    pub fn initInPlace(self: *Locker, allocator: std.mem.Allocator, logger: *?Logger) !void {
        const cfg = loadConfig(allocator, logger);

        self.* = Locker{
            .sequence = toolkit.input.Sequence(queue_capacity).init(),
            .logger = logger,
            .watcher = toolkit.os.Watcher.init(),
            .cfg = cfg,
            .remap_handler = undefined,
            .is_keyboard_locked = cfg.is_keyboard_locked,
            .is_mouse_locked = cfg.is_mouse_locked,
            .show_notification = cfg.show_notification,
            .allocator = allocator,
        };

        self.initializeComponent();
        self.setupIcon();

        try self.setupWindow();

        errdefer self.window.deinit();

        try self.setupTray();
        self.setupContextMenu();
        self.setupTimer();

        instance = self;

        if (self.logger.*) |*l| {
            l.log("Locker is ready", .{});
        }

        std.debug.assert(instance == self);
        std.debug.assert(self.state == .unlocked);
    }

    pub fn deinit(self: *Locker) void {
        std.debug.assert(instance == self);

        if (self.logger.*) |*l| {
            l.log("Shutting down", .{});
        }

        self.watcher.deinit();
        self.rehook_timer.stop();
        self.keyboard_hook.remove();
        self.mouse_hook.remove();
        self.tray.remove();
        self.context_menu.deinit();
        self.icon.lock.deinit();
        self.icon.unlock.deinit();
        self.window.deinit();
        self.cfg.deinit();
    }

    fn checkLockSequence(self: *Locker) bool {
        std.debug.assert(instance == self);

        if (self.lock_sequence) |seq| {
            std.debug.assert(seq.len > 0);

            const matched = self.sequence.matches(seq) catch false;

            if (!matched) {
                return false;
            }

            if (self.state.isLocked()) {
                return false;
            }

            std.debug.assert(!self.state.isLocked());

            self.setState(.locked, "typed lock sequence");

            std.debug.assert(self.state.isLocked());

            return true;
        }

        return false;
    }

    fn checkUnlockSequence(self: *Locker) bool {
        std.debug.assert(instance == self);

        if (self.unlock_sequence) |seq| {
            std.debug.assert(seq.len > 0);

            const matched = self.sequence.matches(seq) catch false;

            if (!matched) {
                return false;
            }

            if (!self.state.isLocked()) {
                return false;
            }

            std.debug.assert(self.state.isLocked());

            self.setState(.unlocked, "typed unlock sequence");

            std.debug.assert(!self.state.isLocked());

            return true;
        }

        return false;
    }

    fn handleKeyDown(self: *Locker, code: u32) bool {
        std.debug.assert(code > 0);
        std.debug.assert(instance == self);

        self.sequence.push(@truncate(code));

        if (self.checkLockSequence()) {
            return true;
        }

        if (self.checkUnlockSequence()) {
            return true;
        }

        return false;
    }

    fn handleMenuCommand(self: *Locker, command: u32) void {
        std.debug.assert(instance == self);

        if (command == constant.Menu.toggle) {
            self.toggleState("selected from menu");
            return;
        }

        if (command == constant.Menu.toggle_keyboard) {
            self.setKeyboardLocked(!self.is_keyboard_locked);
            return;
        }

        if (command == constant.Menu.toggle_mouse) {
            self.setMouseLocked(!self.is_mouse_locked);
            return;
        }

        if (command == constant.Menu.settings) {
            self.openSettings();
            return;
        }

        if (command == constant.Menu.exit) {
            if (self.logger.*) |*l| {
                l.log("Exiting", .{});
            }

            toolkit.os.quit();
            return;
        }
    }

    fn initializeComponent(self: *Locker) void {
        self.remap_handler = RemapHandler.init(&self.cfg, self.logger);
        self.lock_sequence = self.cfg.getLockSequence();
        self.unlock_sequence = self.cfg.getUnlockSequence();
    }

    fn loadConfig(allocator: std.mem.Allocator, logger: *?Logger) Config {
        return Config.load(allocator) catch |err| {
            if (logger.*) |*l| {
                l.log("Could not load config file, using defaults: {}", .{err});
            }

            return Config.init(allocator);
        };
    }

    fn logStateChange(self: *Locker, state: State, reason: []const u8) void {
        std.debug.assert(instance == self);

        if (self.logger.*) |*l| {
            if (state.isLocked()) {
                l.log("Peripherals locked ({s})", .{reason});
            } else {
                l.log("Peripherals unlocked ({s})", .{reason});
            }
        }
    }

    fn refreshHook(self: *Locker) void {
        std.debug.assert(instance == self);

        self.keyboard_hook.remove();
        self.mouse_hook.remove();

        self.keyboard_hook = toolkit.input.Hook.install(.keyboard, keyboardProc);

        if (!self.keyboard_hook.isInstalled()) {
            if (self.logger.*) |*l| {
                l.log("Could not reinstall keyboard hook", .{});
            }
        }

        if (!self.state.isLocked()) {
            return;
        }

        if (!self.is_mouse_locked) {
            return;
        }

        self.mouse_hook = toolkit.input.Hook.install(.mouse, mouseProc);

        if (!self.mouse_hook.isInstalled()) {
            if (self.logger.*) |*l| {
                l.log("Could not install mouse hook", .{});
            }
        }
    }

    fn setupContextMenu(self: *Locker) void {
        self.context_menu = toolkit.ui.Menu.init() orelse {
            if (self.logger.*) |*l| {
                l.log("Failed to create context menu", .{});
            }

            return;
        };
    }

    fn setupIcon(self: *Locker) void {
        self.icon.lock = toolkit.ui.Icon.fromResource(constant.Resource.lock_icon);
        self.icon.unlock = toolkit.ui.Icon.fromResource(constant.Resource.unlock_icon);

        if (!self.icon.lock.isValid()) {
            self.icon.lock = toolkit.ui.Icon.fromSystem(.shield);
        }

        if (!self.icon.unlock.isValid()) {
            self.icon.unlock = toolkit.ui.Icon.fromSystem(.application);
        }
    }

    fn setupTimer(self: *Locker) void {
        self.rehook_timer = toolkit.os.Timer.init(self.window.handle, constant.Timer.rehook_id);
        _ = self.rehook_timer.start(constant.Timer.rehook_interval_ms);
    }

    fn setupTray(self: *Locker) !void {
        self.tray = .{ .hwnd = self.window.handle };

        const icon = if (self.state.isLocked()) self.icon.lock else self.icon.unlock;

        try self.tray.add(icon, "Peripheral Locker");
    }

    fn setupWindow(self: *Locker) !void {
        self.window = try toolkit.os.Window.init(
            std.unicode.utf8ToUtf16LeStringLiteral("Locker"),
            windowProc,
            self,
        );
    }

    fn shouldBlockKey(self: *Locker, event: toolkit.input.KeyEvent) bool {
        std.debug.assert(instance == self);

        if (!self.state.isLocked()) {
            return false;
        }

        if (!self.is_keyboard_locked) {
            return false;
        }

        if (isBlockedKey(event.vk)) {
            return true;
        }

        if (event.is_down) {
            return true;
        }

        return false;
    }

    fn shouldBlockMouse(self: *Locker, event: toolkit.input.MouseEvent) bool {
        std.debug.assert(instance == self);

        if (!self.state.isLocked()) {
            return false;
        }

        if (!self.is_mouse_locked) {
            return false;
        }

        if (event.isButton() or event.kind == .wheel) {
            return true;
        }

        return false;
    }

    fn showStateNotification(self: *Locker, state: State) void {
        std.debug.assert(instance == self);

        if (!self.show_notification) {
            return;
        }

        if (state.isLocked()) {
            self.tray.notify("Peripheral Locker", "Peripheral(s) are locked");
        } else {
            self.tray.notify("Peripheral Locker", "Peripheral(s) are unlocked");
        }
    }

    pub fn openSettings(self: *Locker) void {
        std.debug.assert(instance == self);

        if (self.cfg.getConfigPath()) |path| {
            std.debug.assert(path.len > 0);

            if (self.logger.*) |*l| {
                l.log("Opening settings file", .{});
            }

            shellOpen(path);
        }
    }

    pub fn reloadConfig(self: *Locker) void {
        std.debug.assert(instance == self);

        self.cfg.reset();

        const path = self.cfg.config_path[0..self.cfg.config_path_len];

        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            if (self.logger.*) |*l| {
                l.log("Could not open config file: {}", .{err});
            }

            return;
        };

        defer file.close();

        const alloc = self.cfg.arena.allocator();

        const content = alloc.allocSentinel(u8, Config.content_max, 0) catch {
            if (self.logger.*) |*l| {
                l.log("Could not allocate buffer for config", .{});
            }

            return;
        };

        const count = file.readAll(content) catch |err| {
            if (self.logger.*) |*l| {
                l.log("Could not read config file: {}", .{err});
            }

            return;
        };

        if (count == 0) {
            if (self.logger.*) |*l| {
                l.log("Config file is empty", .{});
            }

            return;
        }

        const slice: [:0]const u8 = content[0..count :0];

        self.cfg.parse(slice) catch |err| {
            if (self.logger.*) |*l| {
                l.log("Could not parse config file: {}", .{err});
            }

            return;
        };

        self.remap_handler = RemapHandler.init(&self.cfg, self.logger);
        self.is_keyboard_locked = self.cfg.is_keyboard_locked;
        self.is_mouse_locked = self.cfg.is_mouse_locked;
        self.show_notification = self.cfg.show_notification;
        self.lock_sequence = self.cfg.getLockSequence();
        self.unlock_sequence = self.cfg.getUnlockSequence();

        self.refreshHook();

        if (self.logger.*) |*l| {
            l.log("Config file reloaded", .{});
        }
    }

    pub fn run(self: *Locker) void {
        std.debug.assert(instance == self);

        self.keyboard_hook = toolkit.input.Hook.install(.keyboard, keyboardProc);

        if (!self.keyboard_hook.isInstalled()) {
            if (self.logger.*) |*l| {
                l.log("Could not install keyboard hook", .{});
            }
        }

        if (self.cfg.getConfigPath()) |path| {
            std.debug.assert(path.len > 0);

            self.watcher.watch(path, onConfigChanged) catch |err| {
                if (self.logger.*) |*l| {
                    l.log("Could not watch config file for changes: {}", .{err});
                }
            };
        }

        toolkit.os.runMessageLoop();
    }

    pub fn setKeyboardLocked(self: *Locker, locked: bool) void {
        std.debug.assert(instance == self);

        self.is_keyboard_locked = locked;
        self.refreshHook();

        std.debug.assert(self.is_keyboard_locked == locked);

        if (self.logger.*) |*l| {
            if (locked) {
                l.log("Keyboard blocking enabled", .{});
            } else {
                l.log("Keyboard blocking disabled", .{});
            }
        }
    }

    pub fn setMouseLocked(self: *Locker, locked: bool) void {
        std.debug.assert(instance == self);

        self.is_mouse_locked = locked;
        self.refreshHook();

        std.debug.assert(self.is_mouse_locked == locked);

        if (self.logger.*) |*l| {
            if (locked) {
                l.log("Mouse blocking enabled", .{});
            } else {
                l.log("Mouse blocking disabled", .{});
            }
        }
    }

    pub fn setState(self: *Locker, state: State, reason: []const u8) void {
        std.debug.assert(state == .locked or state == .unlocked);
        std.debug.assert(instance == self);

        if (self.state == state) {
            return;
        }

        const previous = self.state;

        self.state = state;
        self.refreshHook();

        const icon = if (state.isLocked()) self.icon.lock else self.icon.unlock;
        self.tray.setIcon(icon);

        std.debug.assert(self.state == state);
        std.debug.assert(self.state != previous);

        self.logStateChange(state, reason);
        self.showStateNotification(state);
    }

    pub fn showContextMenu(self: *Locker) void {
        std.debug.assert(instance == self);

        self.context_menu.clear();

        const lock_label = if (self.state.isLocked())
            std.unicode.utf8ToUtf16LeStringLiteral("Unlock")
        else
            std.unicode.utf8ToUtf16LeStringLiteral("Lock");

        self.context_menu.add(0, constant.Menu.toggle, lock_label);
        self.context_menu.addChecked(1, constant.Menu.toggle_keyboard, std.unicode.utf8ToUtf16LeStringLiteral("Keyboard"), self.is_keyboard_locked);
        self.context_menu.addChecked(2, constant.Menu.toggle_mouse, std.unicode.utf8ToUtf16LeStringLiteral("Mouse"), self.is_mouse_locked);
        self.context_menu.addSeparator(3);
        self.context_menu.add(4, constant.Menu.settings, std.unicode.utf8ToUtf16LeStringLiteral("Settings"));
        self.context_menu.addSeparator(5);
        self.context_menu.add(6, constant.Menu.exit, std.unicode.utf8ToUtf16LeStringLiteral("Exit"));

        const command = self.context_menu.show(self.window.handle);

        self.handleMenuCommand(command);
    }

    pub fn toggleState(self: *Locker, reason: []const u8) void {
        std.debug.assert(instance == self);

        const previous = self.state;

        std.debug.assert(previous == .locked or previous == .unlocked);

        self.setState(self.state.toggle(), reason);

        std.debug.assert(self.state != previous);
    }
};

fn isBlockedKey(vk: u32) bool {
    return switch (vk) {
        toolkit.input.VirtualKey.apps,
        toolkit.input.VirtualKey.escape,
        toolkit.input.VirtualKey.space,
        => true,
        else => false,
    };
}

fn keyboardProc(code: c_int, wparam: usize, lparam: isize) callconv(.c) isize {
    if (code < 0) {
        return toolkit.input.Hook.callNext(code, wparam, lparam);
    }

    std.debug.assert(code >= 0);

    const event = toolkit.input.KeyEvent.fromHook(wparam, lparam);

    if (event.extra_info == toolkit.input.injected_flag) {
        return toolkit.input.Hook.callNext(code, wparam, lparam);
    }

    if (instance.remap_handler.process(event.vk, event.is_down, event.extra_info)) |result| {
        if (result == 0) {
            return 1;
        }
    }

    if (event.is_injected) {
        return toolkit.input.Hook.callNext(code, wparam, lparam);
    }

    instance.modifier.update(event.vk, event.is_down);

    if (event.is_down) {
        if (instance.handleKeyDown(event.vk)) {
            return 1;
        }
    }

    if (instance.shouldBlockKey(event)) {
        return 1;
    }

    return toolkit.input.Hook.callNext(code, wparam, lparam);
}

fn mouseProc(code: c_int, wparam: usize, lparam: isize) callconv(.c) isize {
    if (code < 0) {
        return toolkit.input.Hook.callNext(code, wparam, lparam);
    }

    std.debug.assert(code >= 0);

    const event = toolkit.input.MouseEvent.fromHook(wparam, lparam);

    if (instance.shouldBlockMouse(event)) {
        return 1;
    }

    return toolkit.input.Hook.callNext(code, wparam, lparam);
}

fn onConfigChanged() void {
    _ = w32.PostMessageW(instance.window.handle, constant.wm_config_reload, 0, 0);
}

fn shellOpen(path: []const u8) void {
    const path_max: u32 = 512;

    if (path.len == 0 or path.len > path_max) {
        return;
    }

    var wide_buf: [path_max]u16 = undefined;

    const len = std.unicode.utf8ToUtf16Le(&wide_buf, path) catch return;

    if (len == 0 or len >= path_max) {
        return;
    }

    wide_buf[len] = 0;

    _ = w32.ShellExecuteW(
        null,
        std.unicode.utf8ToUtf16LeStringLiteral("open"),
        @ptrCast(&wide_buf),
        null,
        null,
        1,
    );
}

fn windowProc(hwnd: w32.HWND, msg: u32, wparam: usize, lparam: isize) callconv(.c) isize {
    const self = toolkit.os.Window.getContext(Locker, hwnd) orelse {
        return w32.DefWindowProcW(hwnd, msg, wparam, lparam);
    };

    std.debug.assert(instance == self);

    if (msg == self.window.taskbar_restart_msg) {
        if (self.logger.*) |*l| {
            l.log("Taskbar restarted, restoring tray icon", .{});
        }

        const icon = if (self.state.isLocked()) self.icon.lock else self.icon.unlock;

        self.tray.add(icon, "Peripheral Locker") catch |err| {
            if (self.logger.*) |*l| {
                l.log("Failed to restore tray icon: {}", .{err});
            }
        };

        return 0;
    }

    if (msg == toolkit.ui.wm_trayicon) {
        if (toolkit.ui.parseTrayEvent(lparam)) |event| {
            switch (event) {
                .left_click => self.toggleState("clicked tray icon"),
                .right_click => self.showContextMenu(),
                .left_double_click => {},
            }
        }

        return 0;
    }

    if (msg == constant.wm_config_reload) {
        self.reloadConfig();
        return 0;
    }

    if (msg == w32.WM_TIMER) {
        if (wparam == constant.Timer.rehook_id) {
            self.refreshHook();
        }

        return 0;
    }

    if (msg == w32.WM_DESTROY) {
        toolkit.os.quit();
        return 0;
    }

    return w32.DefWindowProcW(hwnd, msg, wparam, lparam);
}

const testing = std.testing;

test "State.isLocked" {
    try testing.expect(State.locked.isLocked());
    try testing.expect(!State.unlocked.isLocked());
}

test "State.toggle" {
    try testing.expectEqual(State.unlocked, State.locked.toggle());
    try testing.expectEqual(State.locked, State.unlocked.toggle());
}

test "State.toggle is reversible" {
    const original = State.locked;
    const toggled = original.toggle().toggle();

    try testing.expectEqual(original, toggled);
}
