const std = @import("std");

const wisp = @import("wisp");

const constant = @import("constant.zig");
const State = @import("state.zig").State;

const App = wisp.App;

pub const MenuManager = struct {
    app: *App,

    pub fn init(app: *App) MenuManager {
        return MenuManager{
            .app = app,
        };
    }

    pub fn build(self: *MenuManager, state: State, keyboard_locked: bool, mouse_locked: bool) void {
        const menu = self.app.get_menu();

        menu.clear();

        menu.add_action(constant.Menu.toggle, state.to_action_string()) catch {};
        menu.add_toggle(constant.Menu.toggle_keyboard, "Keyboard", keyboard_locked) catch {};
        menu.add_toggle(constant.Menu.toggle_mouse, "Mouse", mouse_locked) catch {};
        menu.add_separator() catch {};
        menu.add_action(constant.Menu.setting, "Settings") catch {};
        menu.add_separator() catch {};
        menu.add_action(constant.Menu.exit, "Exit") catch {};
    }
};
