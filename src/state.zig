pub const State = enum(u8) {
    locked = 0,
    unlocked = 1,

    pub fn is_locked(state: State) bool {
        return state == .locked;
    }

    pub fn toggle(state: State) State {
        return switch (state) {
            .locked => .unlocked,
            .unlocked => .locked,
        };
    }

    pub fn to_string(state: State) []const u8 {
        return switch (state) {
            .locked => "locked",
            .unlocked => "unlocked",
        };
    }

    pub fn to_action_string(state: State) []const u8 {
        return switch (state) {
            .locked => "Unlock",
            .unlocked => "Lock",
        };
    }
};
