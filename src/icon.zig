const std = @import("std");

const wisp = @import("wisp");

const constant = @import("constant.zig");
const State = @import("state.zig").State;

const App = wisp.App;
const Icon = wisp.Icon;
const IconBuilder = wisp.IconBuilder;

pub const IconManager = struct {
    app: *App,

    pub fn init(app: *App) IconManager {
        return IconManager{
            .app = app,
        };
    }

    pub fn configure(self: *IconManager) void {
        _ = IconBuilder.init(self.app.get_icon())
            .resource("locked", constant.Resource.lock_icon)
            .resource("unlocked", constant.Resource.unlock_icon)
            .system("locked_fallback", .shield)
            .system("unlocked_fallback", .application)
            .done();

        self.app.get_icon().set_current("unlocked") catch {
            self.app.get_icon().set_current("unlocked_fallback") catch {};
        };
    }

    pub fn get_icon_for_state(self: *IconManager, value: State) ?*const Icon {
        return self.app.get_icon().get(value.to_string());
    }

    pub fn update(self: *IconManager, value: State) void {
        const icon_name = value.to_string();
        const fallback_name = if (value.is_locked()) "locked_fallback" else "unlocked_fallback";

        self.app.get_icon().set_current(icon_name) catch {
            self.app.get_icon().set_current(fallback_name) catch {};
        };

        const icon = self.app.get_icon().get_current() orelse return;

        self.app.get_tray().set_icon(icon) catch {};
    }
};
