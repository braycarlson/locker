const std = @import("std");
const w32 = @import("win32").everything;

const constant = @import("../constant.zig");
const win32 = @import("../os/win32.zig");

pub const MenuAction = enum {
    none,
    toggle,
    toggle_keyboard,
    toggle_mouse,
    settings,
    exit,
};

pub const Menu = struct {
    handle: ?w32.HMENU = null,
    is_initialized: bool = false,

    fn commandToAction(command: i32) MenuAction {
        if (command == constant.Menu.toggle) {
            return .toggle;
        }

        if (command == constant.Menu.toggle_keyboard) {
            return .toggle_keyboard;
        }

        if (command == constant.Menu.toggle_mouse) {
            return .toggle_mouse;
        }

        if (command == constant.Menu.settings) {
            return .settings;
        }

        if (command == constant.Menu.exit) {
            return .exit;
        }

        return .none;
    }

    pub fn init(self: *Menu) bool {
        if (self.is_initialized) {
            return true;
        }

        std.debug.assert(self.handle == null);

        self.handle = w32.CreatePopupMenu();

        if (self.handle != null) {
            self.is_initialized = true;

            std.debug.assert(self.is_initialized);
            std.debug.assert(self.handle != null);

            return true;
        }

        std.debug.assert(self.handle == null);
        std.debug.assert(!self.is_initialized);

        return false;
    }

    pub fn deinit(self: *Menu) void {
        if (self.handle) |h| {
            _ = w32.DestroyMenu(h);
        }

        self.handle = null;
        self.is_initialized = false;

        std.debug.assert(self.handle == null);
        std.debug.assert(!self.is_initialized);
    }

    pub fn clear(self: *Menu) void {
        if (self.handle) |h| {
            var count = w32.GetMenuItemCount(h);
            var iteration: i32 = 0;
            const max_items: i32 = 32;

            while (count > 0 and iteration < max_items) {
                std.debug.assert(iteration < max_items);

                _ = w32.DeleteMenu(h, 0, .{ .BYPOSITION = 1 });
                count -= 1;
                iteration += 1;
            }

            std.debug.assert(iteration <= max_items);
        }
    }

    pub fn addItem(self: *Menu, position: u32, id: usize, label: [:0]const u16, is_checked: bool) void {
        std.debug.assert(id > 0);

        if (self.handle) |h| {
            var flags = w32.MENU_ITEM_FLAGS{ .BYPOSITION = 1 };

            if (is_checked) {
                flags.CHECKED = 1;
            }

            _ = w32.InsertMenuW(h, position, flags, id, label);
        }
    }

    pub fn addSeparator(self: *Menu, position: u32) void {
        if (self.handle) |h| {
            _ = w32.InsertMenuW(h, position, .{ .BYPOSITION = 1, .SEPARATOR = 1 }, 0, null);
        }
    }

    pub fn rebuild(self: *Menu, locked: bool, keyboard_locked: bool, mouse_locked: bool) void {
        self.clear();

        var label: [:0]const u16 = undefined;

        if (locked) {
            label = win32.utf8ToUtf16("Unlock");
        } else {
            label = win32.utf8ToUtf16("Lock");
        }

        self.addItem(0, constant.Menu.toggle, label, false);
        self.addItem(1, constant.Menu.toggle_keyboard, win32.utf8ToUtf16("Keyboard"), keyboard_locked);
        self.addItem(2, constant.Menu.toggle_mouse, win32.utf8ToUtf16("Mouse"), mouse_locked);
        self.addSeparator(3);
        self.addItem(4, constant.Menu.settings, win32.utf8ToUtf16("Settings"), false);
        self.addSeparator(5);
        self.addItem(6, constant.Menu.exit, win32.utf8ToUtf16("Exit"), false);
    }

    pub fn show(self: *Menu, window: w32.HWND) MenuAction {
        const point = win32.getCursorPosition() orelse return .none;
        const handle = self.handle orelse return .none;

        _ = w32.SetForegroundWindow(window);

        const command = w32.TrackPopupMenu(
            handle,
            .{ .RETURNCMD = 1 },
            point.x,
            point.y,
            0,
            window,
            null,
        );

        _ = w32.PostMessageW(window, 0, 0, 0);

        return commandToAction(command);
    }
};
