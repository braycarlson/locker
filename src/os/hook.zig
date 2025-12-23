const std = @import("std");
const w32 = @import("win32").everything;

const win32 = @import("win32.zig");

pub const Hook = struct {
    keyboard: ?w32.HHOOK = null,
    mouse: ?w32.HHOOK = null,
    is_keyboard_installed: bool = false,
    is_mouse_installed: bool = false,

    pub fn installKeyboard(self: *Hook, proc: win32.HookProc) bool {
        std.debug.assert(!self.is_keyboard_installed);
        std.debug.assert(self.keyboard == null);

        const instance = win32.getModuleHandle();

        self.keyboard = win32.setWindowsHook(w32.WH_KEYBOARD_LL, proc, instance);

        if (self.keyboard != null) {
            self.is_keyboard_installed = true;

            std.debug.assert(self.is_keyboard_installed);
            std.debug.assert(self.keyboard != null);

            return true;
        }

        std.debug.assert(self.keyboard == null);
        std.debug.assert(!self.is_keyboard_installed);

        return false;
    }

    pub fn installMouse(self: *Hook, proc: win32.HookProc) bool {
        std.debug.assert(!self.is_mouse_installed);
        std.debug.assert(self.mouse == null);

        const instance = win32.getModuleHandle();

        self.mouse = win32.setWindowsHook(w32.WH_MOUSE_LL, proc, instance);

        if (self.mouse != null) {
            self.is_mouse_installed = true;

            std.debug.assert(self.is_mouse_installed);
            std.debug.assert(self.mouse != null);

            return true;
        }

        std.debug.assert(self.mouse == null);
        std.debug.assert(!self.is_mouse_installed);

        return false;
    }

    pub fn removeAll(self: *Hook) void {
        std.debug.assert(self.is_keyboard_installed == (self.keyboard != null));
        std.debug.assert(self.is_mouse_installed == (self.mouse != null));

        self.removeKeyboard();
        self.removeMouse();

        std.debug.assert(self.keyboard == null);
        std.debug.assert(self.mouse == null);
        std.debug.assert(!self.is_keyboard_installed);
        std.debug.assert(!self.is_mouse_installed);
    }

    pub fn removeKeyboard(self: *Hook) void {
        std.debug.assert(self.is_keyboard_installed == (self.keyboard != null));

        if (self.keyboard) |_| {
            std.debug.assert(self.is_keyboard_installed);

            win32.removeWindowsHook(self.keyboard);
        }

        self.keyboard = null;
        self.is_keyboard_installed = false;

        std.debug.assert(self.keyboard == null);
        std.debug.assert(!self.is_keyboard_installed);
    }

    pub fn removeMouse(self: *Hook) void {
        std.debug.assert(self.is_mouse_installed == (self.mouse != null));

        if (self.mouse) |_| {
            std.debug.assert(self.is_mouse_installed);

            win32.removeWindowsHook(self.mouse);
        }

        self.mouse = null;
        self.is_mouse_installed = false;

        std.debug.assert(self.mouse == null);
        std.debug.assert(!self.is_mouse_installed);
    }
};
