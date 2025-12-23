const std = @import("std");
const w32 = @import("win32").everything;

const config = @import("config.zig");
const constant = @import("constant.zig");
const input = @import("input/sender.zig");
const keycode = @import("input/keycode.zig");
const menu = @import("ui/menu.zig");
const win32 = @import("os/win32.zig");

const CircularBuffer = @import("buffer.zig").CircularBuffer;
const Config = config.Config;
const Hook = @import("os/hook.zig").Hook;
const Logger = @import("logger.zig").Logger;
const RemapHandler = @import("input/remap.zig").Remap;
const Tray = @import("ui/tray.zig").Tray;
const Watcher = @import("os/watcher.zig").Watcher;

pub const State = enum {
    locked,
    unlocked,

    pub fn isLocked(self: State) bool {
        std.debug.assert(self == .locked or self == .unlocked);

        if (self == .locked) {
            return true;
        }

        return false;
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

    state: State = .unlocked,
    is_keyboard_locked: bool = true,
    is_mouse_locked: bool = false,
    show_notification: bool = true,

    modifier: keycode.ModifierSet = .{},

    queue: CircularBuffer,
    logger: *?Logger,
    hook: Hook = .{},
    tray: Tray = .{},
    watcher: Watcher,
    cfg: Config,
    remap: RemapHandler,
    context_menu: menu.Menu = .{},

    lock_sequence: ?[]const u8 = null,
    unlock_sequence: ?[]const u8 = null,

    allocator: std.mem.Allocator,

    fn createQueue(logger: *?Logger) !CircularBuffer {
        const queue = CircularBuffer.init(queue_capacity) catch {
            if (logger.*) |*l| {
                l.log("Failed to allocate key buffer", .{});
            }

            return error.AllocationFailed;
        };

        std.debug.assert(queue.capacity == queue_capacity);

        return queue;
    }

    fn initializeComponents(self: *Locker) void {
        self.remap = RemapHandler.init(&self.cfg, self.logger);
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

    fn setupTray(self: *Locker) !void {
        try self.tray.init(&windowProc, self);
        try self.tray.addIcon(self.state.isLocked(), "Peripheral Locker");
    }

    fn setupContextMenu(self: *Locker) void {
        if (!self.context_menu.init()) {
            if (self.logger.*) |*l| {
                l.log("Failed to create context menu", .{});
            }
        }
    }

    pub fn initInPlace(self: *Locker, allocator: std.mem.Allocator, logger: *?Logger) !void {
        const cfg = loadConfig(allocator, logger);
        const queue = try createQueue(logger);

        self.* = Locker{
            .queue = queue,
            .logger = logger,
            .watcher = Watcher.init(logger),
            .cfg = cfg,
            .remap = undefined,
            .is_keyboard_locked = cfg.is_keyboard_locked,
            .is_mouse_locked = cfg.is_mouse_locked,
            .show_notification = cfg.show_notification,
            .allocator = allocator,
        };

        self.initializeComponents();
        self.setupContextMenu();

        instance = self;

        try self.setupTray();

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
        self.tray.killTimer();
        self.hook.removeAll();
        self.tray.deinit();
        self.context_menu.deinit();
        self.cfg.deinit();
    }

    fn checkLockSequence(self: *Locker) bool {
        std.debug.assert(instance == self);

        if (self.lock_sequence) |seq| {
            std.debug.assert(seq.len > 0);

            const matched = self.queue.isMatch(seq) catch false;

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

            const matched = self.queue.isMatch(seq) catch false;

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

    fn handleKeyDown(self: *Locker, vk_code: u32) bool {
        std.debug.assert(vk_code > 0);
        std.debug.assert(instance == self);

        self.queue.push(@truncate(vk_code));

        if (self.checkLockSequence()) {
            return true;
        }

        if (self.checkUnlockSequence()) {
            return true;
        }

        return false;
    }

    fn refreshHook(self: *Locker) void {
        std.debug.assert(instance == self);

        self.hook.removeAll();

        const keyboard_installed = self.hook.installKeyboard(&keyboardProc);

        if (!keyboard_installed) {
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

        const mouse_installed = self.hook.installMouse(&mouseProc);

        if (!mouse_installed) {
            if (self.logger.*) |*l| {
                l.log("Could not install mouse hook", .{});
            }
        }
    }

    fn shouldBlockKey(self: *Locker, wparam: w32.WPARAM, vk_code: u32) bool {
        std.debug.assert(instance == self);

        if (!self.state.isLocked()) {
            return false;
        }

        if (!self.is_keyboard_locked) {
            return false;
        }

        if (keycode.Keyboard.isBlockedKey(vk_code)) {
            return true;
        }

        if (keycode.Keyboard.isBlockedMessage(wparam)) {
            return true;
        }

        return false;
    }

    fn shouldBlockMouse(self: *Locker, wparam: w32.WPARAM) bool {
        std.debug.assert(instance == self);

        if (!self.state.isLocked()) {
            return false;
        }

        if (!self.is_mouse_locked) {
            return false;
        }

        if (keycode.Mouse.isBlockedMessage(wparam)) {
            return true;
        }

        return false;
    }

    fn updateModifiers(self: *Locker, vk_code: u32, is_down: bool) void {
        std.debug.assert(vk_code > 0);
        std.debug.assert(instance == self);

        switch (vk_code) {
            keycode.VirtualKey.control,
            keycode.VirtualKey.lcontrol,
            keycode.VirtualKey.rcontrol,
            => self.modifier.ctrl = is_down,

            keycode.VirtualKey.menu,
            keycode.VirtualKey.lmenu,
            keycode.VirtualKey.rmenu,
            => self.modifier.alt = is_down,

            keycode.VirtualKey.shift,
            keycode.VirtualKey.lshift,
            keycode.VirtualKey.rshift,
            => self.modifier.shift = is_down,

            keycode.VirtualKey.lwin,
            keycode.VirtualKey.rwin,
            => self.modifier.win = is_down,

            else => {},
        }
    }

    pub fn openSettings(self: *Locker) void {
        std.debug.assert(instance == self);

        if (self.cfg.getConfigPath()) |path| {
            std.debug.assert(path.len > 0);

            if (self.logger.*) |*l| {
                l.log("Opening settings file", .{});
            }

            win32.shellOpen(path);
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

        const arena_alloc = self.cfg.arena.allocator();
        const content = arena_alloc.allocSentinel(u8, Config.content_max, 0) catch {
            if (self.logger.*) |*l| {
                l.log("Could not allocate buffer for config", .{});
            }
            return;
        };

        const bytes_read = file.readAll(content) catch |err| {
            if (self.logger.*) |*l| {
                l.log("Could not read config file: {}", .{err});
            }
            return;
        };

        if (bytes_read == 0) {
            if (self.logger.*) |*l| {
                l.log("Config file is empty", .{});
            }
            return;
        }

        const content_slice: [:0]const u8 = content[0..bytes_read :0];

        self.cfg.parse(content_slice) catch |err| {
            if (self.logger.*) |*l| {
                l.log("Could not parse config file: {}", .{err});
            }
            return;
        };

        self.remap = RemapHandler.init(&self.cfg, self.logger);
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

        const keyboard_installed = self.hook.installKeyboard(&keyboardProc);

        if (!keyboard_installed) {
            if (self.logger.*) |*l| {
                l.log("Could not install keyboard hook", .{});
            }
        }

        self.tray.setTimer();

        if (self.cfg.getConfigPath()) |path| {
            std.debug.assert(path.len > 0);

            self.watcher.start(path, &onConfigChanged) catch |err| {
                if (self.logger.*) |*l| {
                    l.log("Could not watch config file for changes: {}", .{err});
                }
            };
        }

        var msg: w32.MSG = undefined;

        while (w32.GetMessageW(&msg, null, 0, 0) > 0) {
            _ = w32.TranslateMessage(&msg);
            _ = w32.DispatchMessageW(&msg);
        }
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

    fn showStateNotification(self: *Locker, state: State) void {
        std.debug.assert(instance == self);

        if (!self.show_notification) {
            return;
        }

        if (state.isLocked()) {
            self.tray.showNotification("Peripheral Locker", "Peripheral(s) are locked");
        } else {
            self.tray.showNotification("Peripheral Locker", "Peripheral(s) are unlocked");
        }
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

    pub fn setState(self: *Locker, state: State, reason: []const u8) void {
        std.debug.assert(state == .locked or state == .unlocked);
        std.debug.assert(instance == self);

        if (self.state == state) {
            return;
        }

        const previous = self.state;

        self.state = state;
        self.refreshHook();
        self.tray.updateIcon(state.isLocked());

        std.debug.assert(self.state == state);
        std.debug.assert(self.state != previous);

        self.logStateChange(state, reason);
        self.showStateNotification(state);
    }

    pub fn toggleState(self: *Locker, reason: []const u8) void {
        std.debug.assert(instance == self);

        const previous = self.state;

        std.debug.assert(previous == .locked or previous == .unlocked);

        self.setState(self.state.toggle(), reason);

        std.debug.assert(self.state != previous);
    }

    pub fn showContextMenu(self: *Locker, window: w32.HWND) menu.MenuAction {
        std.debug.assert(instance == self);

        self.context_menu.rebuild(
            self.state.isLocked(),
            self.is_keyboard_locked,
            self.is_mouse_locked,
        );

        return self.context_menu.show(window);
    }
};

fn handleMenuAction(self: *Locker, action: menu.MenuAction) void {
    std.debug.assert(instance == self);

    if (action == .toggle) {
        self.toggleState("selected from menu");
        return;
    }

    if (action == .toggle_keyboard) {
        self.setKeyboardLocked(!self.is_keyboard_locked);
        return;
    }

    if (action == .toggle_mouse) {
        self.setMouseLocked(!self.is_mouse_locked);
        return;
    }

    if (action == .settings) {
        self.openSettings();
        return;
    }

    if (action == .exit) {
        if (self.logger.*) |*l| {
            l.log("Exiting", .{});
        }

        win32.postQuit();
        return;
    }
}

fn handleTrayMessage(self: *Locker, window: w32.HWND, lparam: w32.LPARAM) void {
    std.debug.assert(instance == self);

    if (lparam == w32.WM_LBUTTONUP) {
        self.toggleState("clicked tray icon");
        return;
    }

    if (lparam == w32.WM_RBUTTONUP) {
        const action = self.showContextMenu(window);
        handleMenuAction(self, action);
        return;
    }
}

fn isKeyDown(wparam: w32.WPARAM) bool {
    if (wparam == w32.WM_KEYDOWN) {
        return true;
    }

    if (wparam == w32.WM_SYSKEYDOWN) {
        return true;
    }

    return false;
}

fn shouldSkipEvent(event: *w32.KBDLLHOOKSTRUCT) bool {
    if (event.dwExtraInfo == input.shortcut_flag) {
        return true;
    }

    return false;
}

fn shouldBlockFromRemap(event: *w32.KBDLLHOOKSTRUCT, wparam: w32.WPARAM) bool {
    if (instance.remap.process(event.vkCode, isKeyDown(wparam), event.dwExtraInfo)) |result| {
        if (result == 0) {
            return true;
        }
    }

    return false;
}

fn processKeyEvent(event: *w32.KBDLLHOOKSTRUCT, wparam: w32.WPARAM) bool {
    const is_down = isKeyDown(wparam);

    instance.updateModifiers(event.vkCode, is_down);

    if (is_down) {
        if (instance.handleKeyDown(event.vkCode)) {
            return true;
        }
    }

    if (instance.shouldBlockKey(wparam, event.vkCode)) {
        return true;
    }

    return false;
}

fn keyboardProc(code: c_int, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.c) w32.LRESULT {
    if (code < 0) {
        return win32.callNextHook(code, wparam, lparam);
    }

    std.debug.assert(code >= 0);

    const event: *w32.KBDLLHOOKSTRUCT = @ptrFromInt(@as(usize, @intCast(lparam)));

    if (shouldSkipEvent(event)) {
        return win32.callNextHook(code, wparam, lparam);
    }

    std.debug.assert(event.vkCode > 0);

    if (shouldBlockFromRemap(event, wparam)) {
        return 1;
    }

    if (event.flags.INJECTED == 1) {
        return win32.callNextHook(code, wparam, lparam);
    }

    if (processKeyEvent(event, wparam)) {
        return 1;
    }

    return win32.callNextHook(code, wparam, lparam);
}

fn mouseProc(code: c_int, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.c) w32.LRESULT {
    if (code < 0) {
        return win32.callNextHook(code, wparam, lparam);
    }

    std.debug.assert(code >= 0);

    if (instance.shouldBlockMouse(wparam)) {
        return 1;
    }

    return win32.callNextHook(code, wparam, lparam);
}

fn onConfigChanged() void {
    const window = instance.tray.window orelse return;

    const result = w32.PostMessageW(window, constant.wm_config_reload, 0, 0);

    if (result == 0) {
        if (instance.logger.*) |*l| {
            l.log("Could not trigger config reload", .{});
        }
    }
}

fn windowProc(window: w32.HWND, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.c) w32.LRESULT {
    const address: isize = w32.GetWindowLongPtrW(window, w32.GWLP_USERDATA);

    if (address == 0) {
        return w32.DefWindowProcW(window, message, wparam, lparam);
    }

    std.debug.assert(address != 0);

    const self: *Locker = @ptrFromInt(@as(usize, @intCast(address)));

    std.debug.assert(instance == self);

    if (message == self.tray.taskbar_created_msg) {
        if (self.logger.*) |*l| {
            l.log("Taskbar restarted, restoring tray icon", .{});
        }

        self.tray.addIcon(self.state.isLocked(), "Peripheral Locker") catch |err| {
            if (self.logger.*) |*l| {
                l.log("Failed to restore tray icon: {}", .{err});
            }
        };

        return 0;
    }

    if (message == constant.wm_trayicon) {
        handleTrayMessage(self, window, lparam);
        return 0;
    }

    if (message == constant.wm_config_reload) {
        self.reloadConfig();
        return 0;
    }

    if (message == w32.WM_TIMER) {
        if (wparam == constant.Timer.rehook_id) {
            self.refreshHook();
        }
        return 0;
    }

    if (message == w32.WM_DESTROY) {
        win32.postQuit();
        return 0;
    }

    return w32.DefWindowProcW(window, message, wparam, lparam);
}

const testing = std.testing;

test "State.isLocked returns true for locked state" {
    const state = State.locked;

    try testing.expect(state.isLocked());
}

test "State.isLocked returns false for unlocked state" {
    const state = State.unlocked;

    try testing.expect(!state.isLocked());
}

test "State.toggle from locked to unlocked" {
    const state = State.locked;
    const toggled = state.toggle();

    try testing.expectEqual(State.unlocked, toggled);
}

test "State.toggle from unlocked to locked" {
    const state = State.unlocked;
    const toggled = state.toggle();

    try testing.expectEqual(State.locked, toggled);
}

test "State.toggle is reversible" {
    const original = State.locked;
    const toggled_once = original.toggle();
    const toggled_twice = toggled_once.toggle();

    try testing.expectEqual(original, toggled_twice);
}

test "State.toggle unlocked is reversible" {
    const original = State.unlocked;
    const toggled_once = original.toggle();
    const toggled_twice = toggled_once.toggle();

    try testing.expectEqual(original, toggled_twice);
}

test "State equality" {
    try testing.expectEqual(State.locked, State.locked);
    try testing.expectEqual(State.unlocked, State.unlocked);
    try testing.expect(State.locked != State.unlocked);
}
