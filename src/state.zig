const std = @import("std");

pub const State = enum(u8) {
    locked = 0,
    unlocked = 1,

    pub fn is_locked(self: State) bool {
        return self == .locked;
    }

    pub fn toggle(self: State) State {
        return if (self == .locked) State.unlocked else State.locked;
    }

    pub fn to_string(self: State) []const u8 {
        return if (self == .locked) "locked" else "unlocked";
    }

    pub fn to_action_string(self: State) []const u8 {
        return if (self == .locked) "Unlock" else "Lock";
    }
};
