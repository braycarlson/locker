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
        const icon = self.app.get_icon();

        _ = IconBuilder.init(icon)
            .resource("locked", constant.Resource.lock_icon)
            .resource("unlocked", constant.Resource.unlock_icon)
            .system("locked_fallback", .shield)
            .system("unlocked_fallback", .application)
            .done() catch icon;

        icon.set_current("unlocked") catch {
            icon.set_current("unlocked_fallback") catch {};
        };
    }

    pub fn get_icon_for_state(self: *IconManager, value: State) ?*const Icon {
        return self.app.get_icon().get(value.to_string());
    }

    pub fn update(self: *IconManager, value: State) void {
        const manager = self.app.get_icon();
        const icon_name = value.to_string();
        const fallback_name = if (value.is_locked()) "locked_fallback" else "unlocked_fallback";

        manager.set_current(icon_name) catch {
            manager.set_current(fallback_name) catch {};
        };

        const icon = manager.get_current() orelse return;

        self.app.get_tray().set_icon(icon) catch {};
    }
};
