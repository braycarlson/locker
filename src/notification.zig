const std = @import("std");

const wisp = @import("wisp");

const IconManager = @import("icon.zig").IconManager;
const State = @import("state.zig").State;

const App = wisp.App;

pub const NotificationManager = struct {
    app: *App,
    enabled: bool,
    icon: *IconManager,

    pub fn init(app: *App, icon: *IconManager, enabled: bool) NotificationManager {
        return NotificationManager{
            .app = app,
            .enabled = enabled,
            .icon = icon,
        };
    }

    pub fn set_enabled(self: *NotificationManager, value: bool) void {
        self.enabled = value;
    }

    pub fn show(self: *NotificationManager, value: State) void {
        if (!self.enabled) {
            return;
        }

        const icon = self.icon.get_icon_for_state(value) orelse return;

        const message = if (value.is_locked())
            "Peripheral(s) are locked"
        else
            "Peripheral(s) are unlocked";

        self.app.get_tray().show_balloon_with_icon("Peripheral Locker", message, icon) catch {};
    }
};
