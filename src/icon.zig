const std = @import("std");

const umbra = @import("umbra");

const State = @import("state.zig").State;

const assert = std.debug.assert;

const CapacityError = umbra.CapacityError;
const IconBuilder = umbra.IconBuilder;
const IconSet = umbra.IconSet;
const Pixmap = umbra.Icon.Pixmap;
const PlatformError = umbra.PlatformError;
const RequestError = umbra.RequestError;

const dimension: u32 = 32;
const locked = Pixmap.from_rgba(@embedFile("lock.rgba"), dimension);
const unlocked = Pixmap.from_rgba(@embedFile("unlock.rgba"), dimension);

comptime {
    assert(locked.height == dimension);
    assert(unlocked.height == dimension);
}

pub fn register(icons: *IconSet) (CapacityError || RequestError)!void {
    assert(icons.is_empty());

    _ = try IconBuilder.init(icons)
        .pixels(State.locked.to_string(), locked)
        .pixels(State.unlocked.to_string(), unlocked)
        .done();

    assert(!icons.is_empty());
}

pub fn show(icons: *IconSet, state: State) (PlatformError || RequestError)!void {
    const name = state.to_string();

    assert(icons.get_source(name) != null);

    try icons.set_current(name);
}

const testing = std.testing;

fn partial_alpha_count(argb: []const u8) u32 {
    assert(argb.len % 4 == 0);

    var result: u32 = 0;
    var index: usize = 0;

    while (index < argb.len) : (index += 4) {
        const alpha = argb[index];
        if (alpha == 0) continue;
        if (alpha == 255) continue;

        result += 1;
    }

    assert(result <= argb.len / 4);

    return result;
}

test register {
    var icons = IconSet.init();
    defer icons.deinit();

    try register(&icons);
    try show(&icons, .unlocked);

    try testing.expectEqualStrings("unlocked", icons.get_current_name().?);
}

test show {
    var icons = IconSet.init();
    defer icons.deinit();

    try register(&icons);
    try show(&icons, .locked);

    try testing.expectEqualStrings("locked", icons.get_current_name().?);

    try show(&icons, .unlocked);

    try testing.expectEqualStrings("unlocked", icons.get_current_name().?);
}

test "the embedded pixmaps are complete 32 bit images" {
    try testing.expectEqual(dimension * dimension * 4, locked.argb.len);
    try testing.expectEqual(dimension * dimension * 4, unlocked.argb.len);
    try testing.expect(locked.is_valid());
    try testing.expect(unlocked.is_valid());
}

test "each pixmap keeps the antialiasing of the frame it was taken from" {
    try testing.expect(partial_alpha_count(locked.argb) > 0);
    try testing.expect(partial_alpha_count(unlocked.argb) > 0);
}

test "the opaque body of each icon carries the colour its source declares" {
    const offset = (((dimension / 2) * dimension) + 1) * 4;

    try testing.expectEqualSlices(u8, &.{ 0xff, 0xc1, 0x27, 0x2d }, locked.argb[offset..][0..4]);
    try testing.expectEqualSlices(u8, &.{ 0xff, 0xff, 0xff, 0xff }, unlocked.argb[offset..][0..4]);
}
