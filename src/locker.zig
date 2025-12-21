const std = @import("std");
const w32 = @import("win32").everything;

const constant = @import("constant.zig");
const menu = @import("menu.zig");
const win32 = @import("win32.zig");

const CircularBuffer = @import("buffer.zig").CircularBuffer;
const Hook = @import("hook.zig").Hook;
const Logger = @import("logger.zig").Logger;
const Tray = @import("tray.zig").Tray;

pub const State = enum {
    locked,
    unlocked,

    pub fn isLocked(self: State) bool {
        return self == .locked;
    }

    pub fn toggle(self: State) State {
        return if (self == .locked) .unlocked else .locked;
    }
};

var instance: *Locker = undefined;

pub const Locker = struct {
    state: State = .unlocked,
    keyboardLocked: bool = true,
    mouseLocked: bool = false,

    queue: CircularBuffer,
    logger: Logger,
    hook: Hook = .{},
    tray: Tray = .{},

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*Locker {
        var self = try allocator.create(Locker);
        errdefer allocator.destroy(self);

        self.* = Locker{
            .queue = try CircularBuffer.init(allocator, 7),
            .logger = Logger.init(allocator),
            .allocator = allocator,
        };

        self.logger.open() catch {};

        instance = self;

        try self.tray.init(&windowProc, self);
        try self.tray.addIcon(self.state.isLocked(), "Peripheral Locker");

        return self;
    }

    pub fn deinit(self: *Locker) void {
        self.tray.killTimer();
        self.hook.removeAll();
        self.tray.deinit();
        self.logger.deinit();
        self.queue.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *Locker) void {
        _ = self.hook.installKeyboard(&keyboardProc);
        self.tray.setTimer();

        var msg: w32.MSG = undefined;

        while (w32.GetMessageW(&msg, null, 0, 0) > 0) {
            _ = w32.TranslateMessage(&msg);
            _ = w32.DispatchMessageW(&msg);
        }
    }

    pub fn setState(self: *Locker, state: State) void {
        if (self.state == state) return;

        self.state = state;
        self.refreshHook();
        self.tray.updateIcon(state.isLocked());
    }

    pub fn toggleState(self: *Locker) void {
        self.setState(self.state.toggle());
    }

    pub fn setKeyboardLocked(self: *Locker, locked: bool) void {
        self.keyboardLocked = locked;
        self.refreshHook();
    }

    pub fn setMouseLocked(self: *Locker, locked: bool) void {
        self.mouseLocked = locked;
        self.refreshHook();
    }

    fn refreshHook(self: *Locker) void {
        self.hook.removeAll();

        if (!self.hook.installKeyboard(&keyboardProc)) {
            self.logger.log("Failed to install keyboard hook", .{});
        }

        if (self.state.isLocked() and self.mouseLocked) {
            if (!self.hook.installMouse(&mouseProc)) {
                self.logger.log("Failed to install mouse hook", .{});
            }
        }
    }

    fn handleKeyDown(self: *Locker, vkCode: u32) bool {
        self.queue.push(@truncate(vkCode));

        if (self.queue.isMatch(constant.Hotkey.lock) catch false) {
            self.setState(.locked);
            return true;
        }

        if (self.queue.isMatch(constant.Hotkey.unlock) catch false) {
            self.setState(.unlocked);
            return true;
        }

        return false;
    }

    fn shouldBlockKey(self: *Locker, wparam: w32.WPARAM, vkCode: u32) bool {
        if (!self.state.isLocked() or !self.keyboardLocked) return false;

        return constant.Keyboard.isBlockedKey(vkCode) or
            constant.Keyboard.isBlockedMessage(wparam);
    }

    fn shouldBlockMouse(self: *Locker, wparam: w32.WPARAM) bool {
        if (!self.state.isLocked() or !self.mouseLocked) return false;

        return constant.Mouse.isBlockedMessage(wparam);
    }
};

fn keyboardProc(code: c_int, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.c) w32.LRESULT {
    if (code >= 0) {
        const event: *w32.KBDLLHOOKSTRUCT = @ptrFromInt(@as(usize, @intCast(lparam)));

        if (wparam == w32.WM_KEYDOWN or wparam == w32.WM_SYSKEYDOWN) {
            if (instance.handleKeyDown(event.vkCode)) {
                return 1;
            }
        }

        if (instance.shouldBlockKey(wparam, event.vkCode)) {
            return 1;
        }
    }

    return win32.callNextHook(code, wparam, lparam);
}

fn mouseProc(code: c_int, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.c) w32.LRESULT {
    if (code >= 0 and instance.shouldBlockMouse(wparam)) {
        return 1;
    }

    return win32.callNextHook(code, wparam, lparam);
}

fn windowProc(window: w32.HWND, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.c) w32.LRESULT {
    const address: isize = w32.GetWindowLongPtrW(window, w32.GWLP_USERDATA);
    if (address == 0) return w32.DefWindowProcW(window, message, wparam, lparam);

    const self: *Locker = @ptrFromInt(@as(usize, @intCast(address)));

    if (message == self.tray.taskbarCreatedMsg) {
        self.tray.addIcon(self.state.isLocked(), "Peripheral Locker") catch {};
        return 0;
    }

    switch (message) {
        constant.WM_TRAYICON => {
            switch (lparam) {
                w32.WM_LBUTTONUP => self.toggleState(),

                w32.WM_RBUTTONUP => {
                    const action = menu.showContextMenu(
                        window,
                        self.state.isLocked(),
                        self.keyboardLocked,
                        self.mouseLocked,
                    );

                    switch (action) {
                        .toggle => self.toggleState(),
                        .toggleKeyboard => self.setKeyboardLocked(!self.keyboardLocked),
                        .toggleMouse => self.setMouseLocked(!self.mouseLocked),
                        .exit => win32.postQuit(),
                        .none => {},
                    }
                },
                else => {},
            }

            return 0;
        },

        w32.WM_TIMER => {
            if (wparam == constant.Timer.REHOOK_ID) {
                self.refreshHook();
            }

            return 0;
        },

        w32.WM_DESTROY => {
            win32.postQuit();
            return 0;
        },

        else => {},
    }

    return w32.DefWindowProcW(window, message, wparam, lparam);
}
