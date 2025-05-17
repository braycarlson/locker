const std = @import("std");
const w32 = @import("win32").everything;

const constants = @import("constants.zig");
const callback = @import("callback.zig");

const Icon = @import("icon.zig").Icon;
const LockerError = @import("error.zig").LockerError;
const Window = @import("window.zig").Window;

pub const SystemTray = struct {
    window: Window,
    icon: Icon,
    isLocked: bool = false,
    isTimerActive: bool = false,
    isTaskbarCreated: u32 = 0,

    pub fn init(memory: std.mem.Allocator, title: []const u8, state: bool) !*SystemTray {
        var self = try memory.create(SystemTray);
        errdefer memory.destroy(self);

        self.icon = .{};
        try self.icon.init();
        self.isLocked = state;

        const message = std.unicode.utf8ToUtf16LeStringLiteral("TaskbarCreated");
        self.isTaskbarCreated = w32.RegisterWindowMessageW(message);

        self.window = try Window.create(windowProc);

        try self.window.createTrayIcon(self.icon.current(state), title);

        _ = w32.SetWindowLongPtrW(
            self.window.handle,
            w32.GWLP_USERDATA,
            @bitCast(@intFromPtr(self)),
        );

        return self;
    }

    pub fn deinit(self: *SystemTray, memory: std.mem.Allocator) void {
        self.window.removeTrayIcon();
        self.window.destroy();
        self.icon.deinit();
        memory.destroy(self);
    }

    pub fn setLocked(self: *SystemTray, state: bool) void {
        if (self.isLocked == state) return;

        self.isLocked = state;
        self.window.updateIcon(self.icon.current(state));
        callback.invokeToggleLock(state);
    }

    pub fn setToggleLockCallback(self: *SystemTray, handler: *const fn (bool) void) !void {
        _ = self;
        try callback.setToggleLock(handler);
    }

    pub fn setRefreshHookCallback(self: *SystemTray, handler: *const fn () void) !void {
        _ = self;
        try callback.setRefreshHook(handler);
    }

    pub fn setKeyboardLockedCallback(self: *SystemTray, handler: *const fn (bool) void) !void {
        _ = self;
        try callback.setKeyboardLockedCallback(handler);
    }

    pub fn setMouseLockedCallback(self: *SystemTray, handler: *const fn (bool) void) !void {
        _ = self;
        try callback.setMouseLockedCallback(handler);
    }

    pub fn setIsKeyboardLockedCallback(self: *SystemTray, handler: *const fn () bool) !void {
        _ = self;
        try callback.setIsKeyboardLockedCallback(handler);
    }

    pub fn setIsMouseLockedCallback(self: *SystemTray, handler: *const fn () bool) !void {
        _ = self;
        try callback.setIsMouseLockedCallback(handler);
    }

    fn showMenu(self: *SystemTray) void {
        var point: w32.POINT = undefined;
        if (w32.GetCursorPos(&point) == 0) return;

        const menu = w32.CreatePopupMenu() orelse return;
        defer _ = w32.DestroyMenu(menu);

        const unlock: [:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("Unlock");
        const lock: [:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("Lock");
        const keyboard: [:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("Keyboard");
        const mouse: [:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("Mouse");
        const quit: [:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("Exit");

        const label = if (self.isLocked) unlock else lock;

        if (w32.InsertMenuW(menu, 0, w32.MENU_ITEM_FLAGS{ .BYPOSITION = 1 }, constants.MenuIdentifier.TOGGLE, label) == 0) return;

        var keyboard_flags = w32.MENU_ITEM_FLAGS{ .BYPOSITION = 1 };
        if (callback.invokeIsKeyboardLocked()) keyboard_flags.CHECKED = 1;
        if (w32.InsertMenuW(menu, 1, keyboard_flags, constants.MenuIdentifier.TOGGLE_KEYBOARD, keyboard) == 0) return;

        var mouse_flags = w32.MENU_ITEM_FLAGS{ .BYPOSITION = 1 };
        if (callback.invokeIsMouseLocked()) mouse_flags.CHECKED = 1;
        if (w32.InsertMenuW(menu, 2, mouse_flags, constants.MenuIdentifier.TOGGLE_MOUSE, mouse) == 0) return;

        if (w32.InsertMenuW(menu, 3, w32.MENU_ITEM_FLAGS{ .BYPOSITION = 1, .SEPARATOR = 1 }, 0, null) == 0) return;
        if (w32.InsertMenuW(menu, 4, w32.MENU_ITEM_FLAGS{ .BYPOSITION = 1 }, constants.MenuIdentifier.EXIT, quit) == 0) return;

        _ = w32.SetForegroundWindow(self.window.handle);

        const flags = w32.TRACK_POPUP_MENU_FLAGS{ .RETURNCMD = 1 };
        const command = w32.TrackPopupMenu(menu, flags, point.x, point.y, 0, self.window.handle, null);

        switch (command) {
            constants.MenuIdentifier.TOGGLE => self.setLocked(!self.isLocked),

            constants.MenuIdentifier.TOGGLE_KEYBOARD => {
                const current = callback.invokeIsKeyboardLocked();
                callback.invokeSetKeyboardLocked(!current);
            },

            constants.MenuIdentifier.TOGGLE_MOUSE => {
                const current = callback.invokeIsMouseLocked();
                callback.invokeSetMouseLocked(!current);
            },

            constants.MenuIdentifier.EXIT => _ = w32.PostQuitMessage(0),
            else => {},
        }

        _ = w32.PostMessageW(self.window.handle, 0, 0, 0);
    }

    pub fn windowProc(window: w32.HWND, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.C) w32.LRESULT {
        const address: isize = w32.GetWindowLongPtrW(window, w32.GWLP_USERDATA);
        if (address == 0) return w32.DefWindowProcW(window, message, wparam, lparam);

        const pointer: usize = @intCast(address);
        const tray: *SystemTray = @ptrFromInt(pointer);

        if (message == tray.isTaskbarCreated) {
            tray.window.createTrayIcon(tray.icon.current(tray.isLocked), "Peripheral Locker") catch {};
            return 0;
        }

        switch (message) {
            constants.WM_TRAYICON => {
                switch (lparam) {
                    w32.WM_RBUTTONUP => tray.showMenu(),
                    w32.WM_LBUTTONUP => tray.setLocked(!tray.isLocked),
                    else => {},
                }

                return 0;
            },
            w32.WM_TIMER => {
                if (wparam == constants.Timer.REHOOK_ID) {
                    callback.invokeRefreshHook();
                }

                return 0;
            },
            w32.WM_DESTROY => {
                _ = w32.PostQuitMessage(0);
                return 0;
            },
            else => {},
        }

        return w32.DefWindowProcW(window, message, wparam, lparam);
    }
};
