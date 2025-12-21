const w32 = @import("win32").everything;

const win32 = @import("win32.zig");

pub const Hook = struct {
    keyboard: ?w32.HHOOK = null,
    mouse: ?w32.HHOOK = null,

    pub fn installKeyboard(self: *Hook, proc: win32.HookProc) bool {
        const instance = win32.getModuleHandle();
        self.keyboard = win32.setWindowsHook(w32.WH_KEYBOARD_LL, proc, instance);
        return self.keyboard != null;
    }

    pub fn installMouse(self: *Hook, proc: win32.HookProc) bool {
        const instance = win32.getModuleHandle();
        self.mouse = win32.setWindowsHook(w32.WH_MOUSE_LL, proc, instance);
        return self.mouse != null;
    }

    pub fn removeKeyboard(self: *Hook) void {
        win32.removeWindowsHook(self.keyboard);
        self.keyboard = null;
    }

    pub fn removeMouse(self: *Hook) void {
        win32.removeWindowsHook(self.mouse);
        self.mouse = null;
    }

    pub fn removeAll(self: *Hook) void {
        self.removeKeyboard();
        self.removeMouse();
    }
};
