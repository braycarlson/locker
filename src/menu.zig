const std = @import("std");

const nimble = @import("nimble");
const umbra = @import("umbra");

const State = @import("state.zig").State;

const assert = std.debug.assert;

const Blocked = nimble.remote.Client.Blocked;
const CapacityError = umbra.CapacityError;

pub const Command = enum(u32) {
    exit = 1002,
    setting = 1005,
    toggle = 1001,
    toggle_keyboard = 1003,
    toggle_mouse = 1004,
    _,
};

pub fn fill(
    comptime App: type,
    menu: *App.Menu,
    state: State,
    peripherals: Blocked,
) CapacityError!void {
    menu.clear();

    assert(menu.is_empty());

    _ = try App.MenuBuilder.init(menu)
        .action(@backingInt(Command.toggle), state.to_label())
        .toggle(
            @backingInt(Command.toggle_keyboard),
            "Keyboard",
            .{ .checked = peripherals.keyboard },
        )
        .toggle(@backingInt(Command.toggle_mouse), "Mouse", .{ .checked = peripherals.mouse })
        .separator()
        .action(@backingInt(Command.setting), "Settings")
        .separator()
        .action(@backingInt(Command.exit), "Exit")
        .done();

    assert(!menu.is_empty());
}

const testing = std.testing;

const FakeApp = umbra.AppType(umbra.Fake);

test fill {
    const app = try testing.allocator.create(FakeApp);
    defer testing.allocator.destroy(app);

    try app.init(.{ .name = "locker" });
    defer app.deinit();

    const menu = &app.menu;
    const exit = @backingInt(Command.exit);
    const keyboard = @backingInt(Command.toggle_keyboard);
    const mouse = @backingInt(Command.toggle_mouse);
    const toggle = @backingInt(Command.toggle);

    try fill(FakeApp, menu, .unlocked, .{ .keyboard = true });

    try testing.expectEqualStrings("Lock", menu.get_item(toggle).?.get_label());
    try testing.expect(menu.is_checked(keyboard));
    try testing.expect(!menu.is_checked(mouse));
    try testing.expectEqualStrings("Exit", menu.get_item(exit).?.get_label());

    try fill(FakeApp, menu, .locked, .{ .mouse = true });

    try testing.expectEqualStrings("Unlock", menu.get_item(toggle).?.get_label());
    try testing.expect(!menu.is_checked(keyboard));
    try testing.expect(menu.is_checked(mouse));
}
