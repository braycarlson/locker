const std = @import("std");

const umbra = @import("umbra");

const constant = @import("constant.zig");
const State = @import("state.zig").State;

const assert = std.debug.assert;

const App = umbra.App;

pub const MenuManager = struct {
    app: *App,

    pub fn init(app: *App) MenuManager {
        const result = MenuManager{
            .app = app,
        };

        return result;
    }

    pub fn build(
        manager: *MenuManager,
        state: State,
        is_keyboard_locked: bool,
        is_mouse_locked: bool,
    ) void {
        const menu = &manager.app.menu;

        menu.clear();

        assert(menu.is_empty());

        menu.add_action(constant.Menu.toggle, state.to_action_string()) catch {
            return;
        };

        menu.add_toggle(constant.Menu.toggle_keyboard, "Keyboard", is_keyboard_locked) catch {
            return;
        };

        menu.add_toggle(constant.Menu.toggle_mouse, "Mouse", is_mouse_locked) catch {
            return;
        };

        menu.add_separator() catch {
            return;
        };

        menu.add_action(constant.Menu.setting, "Settings") catch {
            return;
        };

        menu.add_separator() catch {
            return;
        };

        menu.add_action(constant.Menu.exit, "Exit") catch {
            return;
        };

        assert(!menu.is_empty());
    }

    pub fn push(manager: *MenuManager) void {
        const menu = &manager.app.menu;

        menu.build() catch {
            return;
        };
    }
};
