const std = @import("std");

const arc = @import("arc");
const nimble = @import("nimble");

const Combination = @import("config.zig").Combination;
const Config = @import("config.zig").Config;

const assert = std.debug.assert;

const modifier = nimble.modifier;

const Client = nimble.remote.Client;
const Key = nimble.Key;
const Keycode = nimble.Keycode;
const Logger = arc.Logger;
const Response = nimble.Response;

pub const Remap = struct {
    configuration: *Config,
    client: *Client,
    logger: ?*Logger,
    shortcut_invoked: bool = false,

    pub fn init(configuration: *Config, client: *Client, logger: ?*Logger) Remap {
        return Remap{
            .configuration = configuration,
            .client = client,
            .logger = logger,
        };
    }

    pub fn process(remap: *Remap, key: *const Key) ?Response {
        if (key.injected) {
            return null;
        }

        if (is_super_key(key.value)) {
            return remap.handle_super_key(key);
        }

        if (!key.down or key.value.is_modifier()) {
            return null;
        }

        if (!key.modifiers.win()) {
            return null;
        }

        if (remap.configuration.is_disabled(key)) {
            remap.shortcut_invoked = true;
            remap.log("Blocked a disabled shortcut");

            return .consume;
        }

        if (remap.configuration.find_remap_entry(key)) |entry| {
            remap.shortcut_invoked = true;
            remap.log("Remapped a shortcut");
            remap.send_remapped_shortcut(&entry.from, &entry.to);

            return .consume;
        }

        return null;
    }

    fn handle_super_key(remap: *Remap, key: *const Key) ?Response {
        assert(is_super_key(key.value));

        if (key.down) {
            remap.shortcut_invoked = false;

            return null;
        }

        if (!remap.shortcut_invoked) {
            return null;
        }

        remap.shortcut_invoked = false;

        remap.client.simulate_key(key.value, .suppress);

        return .consume;
    }

    fn send_remapped_shortcut(
        remap: *Remap,
        from: *const Combination,
        to: *const Combination,
    ) void {
        assert(from.is_valid());
        assert(to.is_valid());

        const from_array = from.modifier_set.to_array();
        const to_array = to.modifier_set.to_array();

        for (0..modifier.kind_count) |kind_index| {
            if (from_array[kind_index]) |modifier_kind| {
                if (!is_modifier_in_set(&to_array, modifier_kind)) {
                    remap.client.simulate_key(modifier_kind.to_keycode(), .up);
                }
            }
        }

        for (0..modifier.kind_count) |kind_index| {
            if (to_array[kind_index]) |modifier_kind| {
                if (!is_modifier_in_set(&from_array, modifier_kind)) {
                    remap.client.simulate_key(modifier_kind.to_keycode(), .down);
                }
            }
        }

        remap.client.simulate_key(to.value, .press);

        var release_index: usize = modifier.kind_count;

        while (release_index > 0) {
            release_index -= 1;

            if (to_array[release_index]) |modifier_kind| {
                if (!is_modifier_in_set(&from_array, modifier_kind)) {
                    remap.client.simulate_key(modifier_kind.to_keycode(), .up);
                }
            }
        }
    }

    fn log(remap: *Remap, message: []const u8) void {
        assert(message.len > 0);

        if (remap.logger) |logger| {
            logger.info(message, &.{}, @src());
        }
    }
};

fn is_modifier_in_set(
    array: *const [modifier.kind_count]?modifier.Kind,
    target: modifier.Kind,
) bool {
    for (array) |item| {
        if (item) |modifier_kind| {
            if (modifier_kind == target) {
                return true;
            }
        }
    }

    return false;
}

fn is_super_key(value: Keycode) bool {
    return value == .super or value == .super_left or value == .super_right;
}

const testing = std.testing;

test "an injected key is never processed" {
    var configuration = Config.init(testing.io);
    defer configuration.deinit();

    var client = nimble.remote.Client{};
    var remap = Remap.init(&configuration, &client, null);

    const injected = Key{
        .value = .a,
        .down = true,
        .injected = true,
        .modifiers = modifier.Set.from(.{ .win = true }),
    };

    try testing.expect(remap.process(&injected) == null);
}

test "a key without the super modifier passes through" {
    var configuration = Config.init(testing.io);
    defer configuration.deinit();

    var client = nimble.remote.Client{};
    var remap = Remap.init(&configuration, &client, null);

    const plain = Key{ .value = .a, .down = true };

    try testing.expect(remap.process(&plain) == null);
}

test "a super release without an invoked shortcut passes through" {
    var configuration = Config.init(testing.io);
    defer configuration.deinit();

    var client = nimble.remote.Client{};
    var remap = Remap.init(&configuration, &client, null);

    const released = Key{ .value = .super_left, .down = false };

    try testing.expect(remap.process(&released) == null);
    try testing.expect(!remap.shortcut_invoked);
}
