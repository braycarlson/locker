const std = @import("std");

const nimble = @import("nimble");

const keycode = nimble.keycode;
const modifier = nimble.modifier;
const simulate = nimble.simulate.key;

const Config = @import("config.zig").Config;
const Combination = @import("config.zig").Combination;
const Logger = @import("logger.zig").Logger;

pub const Remap = struct {
    configuration: *Config,
    logger: ?*Logger,
    shortcut_invoked: bool = false,

    pub fn init(configuration: *Config, logger: ?*Logger) Remap {
        return Remap{
            .configuration = configuration,
            .logger = logger,
        };
    }

    pub fn process(self: *Remap, value: u8, is_down: bool, extra: usize) ?u32 {
        std.debug.assert(keycode.is_valid(value));

        if (extra == simulate.marker_injected) {
            return null;
        }

        if (is_win_key(value)) {
            return self.handle_win_key(value, is_down);
        }

        if (!is_down or keycode.is_modifier(value)) {
            return null;
        }

        const current = modifier.Set.poll();

        if (!current.win()) {
            return null;
        }

        if (self.configuration.is_disabled(value, &current)) {
            self.shortcut_invoked = true;
            self.log("Blocked a disabled shortcut");
            return 0;
        }

        if (self.configuration.find_remap_entry(value, &current)) |entry| {
            self.shortcut_invoked = true;
            self.log("Remapped a shortcut");
            send_remapped_shortcut(&entry.from, &entry.to);
            return 0;
        }

        return null;
    }

    fn handle_win_key(self: *Remap, value: u8, is_down: bool) ?u32 {
        if (is_down) {
            self.shortcut_invoked = false;
            return null;
        }

        if (!self.shortcut_invoked) {
            return null;
        }

        self.shortcut_invoked = false;

        _ = simulate.suppress(value);

        return 0;
    }

    fn log(self: *Remap, message: []const u8) void {
        if (self.logger) |logger| {
            logger.log("{s}", .{message});
        }
    }
};

fn is_modifier_in_set(array: *const [modifier.kind_count]?modifier.Kind, target: modifier.Kind) bool {
    for (array) |item| {
        if (item) |modifier_kind| {
            if (modifier_kind == target) {
                return true;
            }
        }
    }

    return false;
}

fn is_win_key(value: u8) bool {
    return value == keycode.lwin or value == keycode.rwin;
}

fn send_remapped_shortcut(from: *const Combination, to: *const Combination) void {
    std.debug.assert(from.is_valid());
    std.debug.assert(to.is_valid());

    const from_array = from.modifier_set.to_array();
    const to_array = to.modifier_set.to_array();

    _ = simulate.dummy();

    for (0..modifier.kind_count) |i| {
        if (from_array[i]) |modifier_kind| {
            if (!is_modifier_in_set(&to_array, modifier_kind)) {
                _ = simulate.key_up(modifier_kind.to_keycode());
            }
        }
    }

    for (0..modifier.kind_count) |i| {
        if (to_array[i]) |modifier_kind| {
            if (!is_modifier_in_set(&from_array, modifier_kind)) {
                _ = simulate.key_down(modifier_kind.to_keycode());
            }
        }
    }

    _ = simulate.press(to.value);

    var release_index: usize = modifier.kind_count;

    while (release_index > 0) {
        release_index -= 1;

        if (to_array[release_index]) |modifier_kind| {
            if (!is_modifier_in_set(&from_array, modifier_kind)) {
                _ = simulate.key_up(modifier_kind.to_keycode());
            }
        }
    }
}
