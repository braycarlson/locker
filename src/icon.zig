const std = @import("std");

const umbra = @import("umbra");

const constant = @import("constant.zig");
const State = @import("state.zig").State;

const assert = std.debug.assert;

const App = umbra.App;
const IconBuilder = umbra.IconBuilder;
const IconError = umbra.IconError;
const IconPixmap = umbra.IconPixmap;

pub const channel_count: u32 = 4;
pub const pixmap_bytes: u32 = constant.Icon.dimension * constant.Icon.dimension * channel_count;

const locked_argb = to_argb(@embedFile("lock.rgba"));
const unlocked_argb = to_argb(@embedFile("unlock.rgba"));

comptime {
    assert(channel_count == 4);
    assert(constant.Icon.dimension > 0);
    assert(locked_argb.len == pixmap_bytes);
    assert(unlocked_argb.len == pixmap_bytes);
}

pub const IconManager = struct {
    app: *App,

    pub fn init(app: *App) IconManager {
        const result = IconManager{
            .app = app,
        };

        return result;
    }

    pub fn configure(manager: *IconManager) IconError!void {
        _ = try IconBuilder.init(&manager.app.icon)
            .pixels("locked", pixmap(&locked_argb))
            .pixels("unlocked", pixmap(&unlocked_argb))
            .stock("locked_fallback", .shield)
            .stock("unlocked_fallback", .application)
            .done();

        manager.update(.unlocked);
    }

    pub fn update(icon_manager: *IconManager, value: State) void {
        const manager = &icon_manager.app.icon;

        manager.set_current(value.to_string()) catch {
            manager.set_current(fallback_of(value)) catch {
                return;
            };
        };
    }
};

fn fallback_of(value: State) []const u8 {
    const result = switch (value) {
        .locked => "locked_fallback",
        .unlocked => "unlocked_fallback",
    };

    assert(result.len > 0);

    return result;
}

fn pixmap(argb: []const u8) IconPixmap {
    assert(argb.len == pixmap_bytes);

    const result = IconPixmap.init(argb, constant.Icon.dimension, constant.Icon.dimension);

    assert(result.is_valid());

    return result;
}

fn to_argb(comptime rgba: []const u8) [rgba.len]u8 {
    @setEvalBranchQuota(rgba.len * 8);

    var result: [rgba.len]u8 = undefined;
    var index: usize = 0;

    while (index + channel_count <= rgba.len) : (index += channel_count) {
        result[index + 0] = rgba[index + 3];
        result[index + 1] = rgba[index + 0];
        result[index + 2] = rgba[index + 1];
        result[index + 3] = rgba[index + 2];
    }

    return result;
}

const testing = std.testing;

test "the embedded pixmaps are complete 32 bit images" {
    try testing.expectEqual(pixmap_bytes, locked_argb.len);
    try testing.expectEqual(pixmap_bytes, unlocked_argb.len);
    try testing.expect(pixmap(&locked_argb).is_valid());
    try testing.expect(pixmap(&unlocked_argb).is_valid());
}

test "to_argb moves the alpha channel in front of the colour channels" {
    const rgba = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const argb = to_argb(&rgba);

    try testing.expectEqualSlices(u8, &.{ 4, 1, 2, 3, 8, 5, 6, 7 }, &argb);
}

test "each pixmap keeps the antialiasing of the frame it was taken from" {
    const Alpha = struct {
        fn partial_count(argb: []const u8) u32 {
            assert(argb.len == pixmap_bytes);
            assert(argb.len % channel_count == 0);

            var result: u32 = 0;
            var index: usize = 0;

            while (index < argb.len) : (index += channel_count) {
                const alpha = argb[index];

                if (alpha > 0 and alpha < 255) result += 1;
            }

            assert(result <= pixmap_bytes / channel_count);

            return result;
        }
    };

    try testing.expect(Alpha.partial_count(&locked_argb) > 0);
    try testing.expect(Alpha.partial_count(&unlocked_argb) > 0);
}

test "the opaque body of each icon carries the colour its source declares" {
    const row: u32 = constant.Icon.dimension / 2;
    const column: u32 = 1;

    const offset = ((row * constant.Icon.dimension) + column) * channel_count;

    try testing.expectEqualSlices(
        u8,
        &.{ 0xff, 0xc1, 0x27, 0x2d },
        locked_argb[offset..][0..channel_count],
    );

    try testing.expectEqualSlices(
        u8,
        &.{ 0xff, 0xff, 0xff, 0xff },
        unlocked_argb[offset..][0..channel_count],
    );
}

test "every fallback name is distinct from the state name" {
    try testing.expectEqualStrings("locked_fallback", fallback_of(.locked));
    try testing.expectEqualStrings("unlocked_fallback", fallback_of(.unlocked));
    try testing.expect(!std.mem.eql(u8, fallback_of(.locked), State.locked.to_string()));
}
