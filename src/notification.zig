const std = @import("std");

const umbra = @import("umbra");

const State = @import("state.zig").State;

const assert = std.debug.assert;

const App = umbra.App;

pub const title = "Peripheral Locker";

comptime {
    assert(title.len > 0);
}

pub const NotificationManager = struct {
    app: *App,
    enabled: bool,

    pub fn init(app: *App, enabled: bool) NotificationManager {
        return NotificationManager{
            .app = app,
            .enabled = enabled,
        };
    }

    pub fn set_enabled(manager: *NotificationManager, value: bool) void {
        manager.enabled = value;

        assert(manager.enabled == value);
    }

    pub fn show(manager: *NotificationManager, value: State) void {
        if (!manager.enabled) {
            return;
        }

        const body = body_of(value);

        assert(body.len > 0);

        manager.app.notification.send_simple(title, body) catch {
            return;
        };
    }
};

fn body_of(value: State) []const u8 {
    const result = switch (value) {
        .locked => "Peripheral(s) are locked",
        .unlocked => "Peripheral(s) are unlocked",
    };

    assert(result.len > 0);

    return result;
}

const testing = std.testing;

test "every state carries a distinct notification body" {
    try testing.expectEqualStrings("Peripheral(s) are locked", body_of(.locked));
    try testing.expectEqualStrings("Peripheral(s) are unlocked", body_of(.unlocked));
    try testing.expect(!std.mem.eql(u8, body_of(.locked), body_of(.unlocked)));
}
