const std = @import("std");

const arc = @import("arc");
const nimble = @import("nimble");

const Config = @import("config.zig").Config;

const assert = std.debug.assert;

const Client = nimble.remote.Client;
const Combination = Config.Combination;
const Key = nimble.Key;
const Keycode = nimble.Keycode;
const Logger = arc.Logger;
const Modifier = nimble.Modifier;
const Response = nimble.Response;

pub const Remap = struct {
    client: *Client,
    configuration: *const Config,
    logger: ?*const Logger,
    shortcut_invoked: bool,

    pub fn init(configuration: *const Config, client: *Client, logger: ?*const Logger) Remap {
        return Remap{
            .client = client,
            .configuration = configuration,
            .logger = logger,
            .shortcut_invoked = false,
        };
    }

    pub fn process(remap: *Remap, key: *const Key) ?Response {
        if (key.injected) {
            return null;
        }

        if (is_super_key(key.value)) {
            return remap.handle_super_key(key);
        }

        if (!key.down) {
            return null;
        }

        if (key.value.is_modifier()) {
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

        if (remap.configuration.remap_for(key)) |rule| {
            remap.shortcut_invoked = true;

            remap.log("Remapped a shortcut");
            remap.send_remapped_shortcut(&rule.from, &rule.to);

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

        remap.send(key.value, .suppress);

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

        remap.send(to.value, .dummy);

        for (0..Modifier.kind_count) |kind_index| {
            if (from_array[kind_index]) |modifier_kind| {
                if (!is_modifier_in_set(&to_array, modifier_kind)) {
                    remap.send(modifier_kind.to_keycode(), .up);
                }
            }
        }

        for (0..Modifier.kind_count) |kind_index| {
            if (to_array[kind_index]) |modifier_kind| {
                if (!is_modifier_in_set(&from_array, modifier_kind)) {
                    remap.send(modifier_kind.to_keycode(), .down);
                }
            }
        }

        remap.send(to.value, .press);

        var release_index: usize = Modifier.kind_count;

        while (release_index > 0) {
            release_index -= 1;

            if (to_array[release_index]) |modifier_kind| {
                if (!is_modifier_in_set(&from_array, modifier_kind)) {
                    remap.send(modifier_kind.to_keycode(), .up);
                }
            }
        }
    }

    fn send(remap: *Remap, value: Keycode, action: Client.KeyAction) void {
        remap.client.simulate_key(value, action) catch {
            remap.log("Unable to send a remapped key");
        };
    }

    fn log(remap: *Remap, message: []const u8) void {
        assert(message.len > 0);

        if (remap.logger) |logger| {
            logger.information(message, &.{}, &@src());
        }
    }
};

fn is_modifier_in_set(
    array: *const [Modifier.kind_count]?Modifier.Kind,
    target: Modifier.Kind,
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

test Remap {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try fixture.parse(
        \\disabled = [{ key = "e", modifiers = ["win"] }]
    );

    var client = Client{};
    var remap = Remap.init(fixture, &client, null);

    const explorer = Key{ .value = .e, .down = true, .modifiers = Modifier.from(.{ .win = true }) };
    const typed = Key{ .value = .e, .down = true };

    try testing.expectEqual(Response.consume, remap.process(&explorer).?);
    try testing.expect(remap.shortcut_invoked);
    try testing.expect(remap.process(&typed) == null);
}

test "an injected key is never processed" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    var client = Client{};
    var remap = Remap.init(fixture, &client, null);

    const injected = Key{
        .value = .a,
        .down = true,
        .injected = true,
        .modifiers = Modifier.from(.{ .win = true }),
    };

    try testing.expect(remap.process(&injected) == null);
}

test "a key without the super modifier passes through" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    var client = Client{};
    var remap = Remap.init(fixture, &client, null);

    const plain = Key{ .value = .a, .down = true };

    try testing.expect(remap.process(&plain) == null);
}

test "a super release without an invoked shortcut passes through" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    var client = Client{};
    var remap = Remap.init(fixture, &client, null);

    const released = Key{ .value = .super_left, .down = false };

    try testing.expect(remap.process(&released) == null);
    try testing.expect(!remap.shortcut_invoked);
}
