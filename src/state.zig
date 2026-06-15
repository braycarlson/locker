pub const State = enum(u8) {
    locked = 0,
    unlocked = 1,

    pub fn is_locked(self: State) bool {
        return self == .locked;
    }

    pub fn toggle(self: State) State {
        return switch (self) {
            .locked => .unlocked,
            .unlocked => .locked,
        };
    }

    pub fn to_string(self: State) []const u8 {
        return switch (self) {
            .locked => "locked",
            .unlocked => "unlocked",
        };
    }

    pub fn to_action_string(self: State) []const u8 {
        return switch (self) {
            .locked => "Unlock",
            .unlocked => "Lock",
        };
    }
};
