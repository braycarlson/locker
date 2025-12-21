const w32 = @import("win32").everything;

const constant = @import("constant.zig");
const win32 = @import("win32.zig");

pub const MenuAction = enum {
    none,
    toggle,
    toggleKeyboard,
    toggleMouse,
    exit,
};

pub const Menu = struct {
    handle: ?w32.HMENU = null,

    pub fn create(self: *Menu) bool {
        self.handle = w32.CreatePopupMenu();
        return self.handle != null;
    }

    pub fn destroy(self: *Menu) void {
        if (self.handle) |h| {
            _ = w32.DestroyMenu(h);
            self.handle = null;
        }
    }

    pub fn addItem(self: *Menu, position: u32, id: usize, label: [:0]const u16, checked: bool) void {
        if (self.handle) |h| {
            var flags = w32.MENU_ITEM_FLAGS{ .BYPOSITION = 1 };

            if (checked) flags.CHECKED = 1;
            _ = w32.InsertMenuW(h, position, flags, id, label);
        }
    }

    pub fn addSeparator(self: *Menu, position: u32) void {
        if (self.handle) |h| {
            _ = w32.InsertMenuW(h, position, .{ .BYPOSITION = 1, .SEPARATOR = 1 }, 0, null);
        }
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

        return switch (command) {
            constant.Menu.TOGGLE => .toggle,
            constant.Menu.TOGGLE_KEYBOARD => .toggleKeyboard,
            constant.Menu.TOGGLE_MOUSE => .toggleMouse,
            constant.Menu.EXIT => .exit,
            else => .none,
        };
    }
};

pub fn showContextMenu(window: w32.HWND, locked: bool, keyboardLocked: bool, mouseLocked: bool) MenuAction {
    var menu = Menu{};

    if (!menu.create()) return .none;
    defer menu.destroy();

    const toggleLabel = if (locked)
        win32.utf8ToUtf16("Unlock")
    else
        win32.utf8ToUtf16("Lock");

    menu.addItem(0, constant.Menu.TOGGLE, toggleLabel, false);
    menu.addItem(1, constant.Menu.TOGGLE_KEYBOARD, win32.utf8ToUtf16("Keyboard"), keyboardLocked);
    menu.addItem(2, constant.Menu.TOGGLE_MOUSE, win32.utf8ToUtf16("Mouse"), mouseLocked);
    menu.addSeparator(3);
    menu.addItem(4, constant.Menu.EXIT, win32.utf8ToUtf16("Exit"), false);

    return menu.show(window);
}
