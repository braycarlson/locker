const std = @import("std");

pub const State = enum(u8) {
    locked = 0,
    unlocked = 1,

    pub fn is_locked(state: State) bool {
        return state == .locked;
    }

    pub fn to_label(state: State) []const u8 {
        return switch (state) {
            .locked => "Unlock",
            .unlocked => "Lock",
        };
    }

    pub fn to_notification_body(state: State) []const u8 {
        return switch (state) {
            .locked => "Peripheral(s) are locked",
            .unlocked => "Peripheral(s) are unlocked",
        };
    }

    pub fn to_string(state: State) []const u8 {
        return switch (state) {
            .locked => "locked",
            .unlocked => "unlocked",
        };
    }
};

const testing = std.testing;

test State {
    const states = [_]State{ .locked, .unlocked };

    for (states) |state| {
        try testing.expect(state.to_label().len > 0);
        try testing.expect(state.to_notification_body().len > 0);
        try testing.expect(state.to_string().len > 0);
    }

    try testing.expect(State.locked.is_locked());
    try testing.expect(!State.unlocked.is_locked());
    try testing.expectEqualStrings("Lock", State.unlocked.to_label());
    try testing.expectEqualStrings("Peripheral(s) are locked", State.locked.to_notification_body());
    try testing.expectEqualStrings("unlocked", State.unlocked.to_string());

    try testing.expect(!std.mem.eql(
        u8,
        State.locked.to_notification_body(),
        State.unlocked.to_notification_body(),
    ));
}
