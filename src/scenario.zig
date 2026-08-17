const std = @import("std");

const nimble = @import("nimble");
const umbra = @import("umbra");

const Application = @import("application.zig").Application;
const constant = @import("constant.zig");
const State = @import("state.zig").State;

const Event = umbra.Event;
const Response = umbra.Response;

const testing = std.testing;

fn open(application: *Application) !void {
    nimble.mock.reset();

    try application.init(testing.io, null);
}

fn label_of(application: *const Application, id: u32) []const u8 {
    const item = application.app.menu.get_item(id) orelse return "";

    return item.get_label();
}

test "a fresh application is unlocked with nothing blocked" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    try testing.expectEqual(State.unlocked, application.state);
    try testing.expectEqualStrings("unlocked", application.app.icon.get_current_name().?);
    try testing.expectEqualStrings("Lock", label_of(&application, constant.Menu.toggle));
    try testing.expectEqualStrings("Exit", label_of(&application, constant.Menu.exit));
    try testing.expect(!application.keyboard_blocked());
    try testing.expect(!application.mouse_blocked());
    try testing.expectEqual(@as(u32, 0), application.app.notification.sent_count());
}

test "a posted lock blocks the keyboard and updates the surface" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.lock);

    try testing.expectEqual(State.locked, application.state);
    try testing.expectEqualStrings("locked", application.app.icon.get_current_name().?);
    try testing.expectEqualStrings("Unlock", label_of(&application, constant.Menu.toggle));
    try testing.expect(application.keyboard_blocked());
    try testing.expect(!application.mouse_blocked());
    try testing.expectEqual(@as(u32, 1), application.app.notification.sent_count());
}

test "a posted unlock releases every block" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.lock);
    application.on_custom(constant.Message.unlock);

    try testing.expectEqual(State.unlocked, application.state);
    try testing.expectEqualStrings("unlocked", application.app.icon.get_current_name().?);
    try testing.expect(!application.keyboard_blocked());
    try testing.expect(!application.mouse_blocked());
    try testing.expectEqual(@as(u32, 2), application.app.notification.sent_count());
}

test "a repeated lock is idempotent" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.lock);
    application.on_custom(constant.Message.lock);

    try testing.expectEqual(State.locked, application.state);
    try testing.expectEqual(@as(u32, 1), application.app.notification.sent_count());
}

test "an unknown custom code leaves the application alone" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.unlock + 100);

    try testing.expectEqual(State.unlocked, application.state);
    try testing.expectEqual(@as(u32, 0), application.app.notification.sent_count());
}

test "the menu toggle drives the same transition as a posted code" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_menu_select(constant.Menu.toggle);

    try testing.expectEqual(State.locked, application.state);

    application.on_menu_select(constant.Menu.toggle);

    try testing.expectEqual(State.unlocked, application.state);
}

test "the peripheral toggles gate what a lock blocks" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_menu_select(constant.Menu.toggle_keyboard);

    try testing.expect(!application.is_keyboard_locked);

    application.on_menu_select(constant.Menu.toggle_mouse);

    try testing.expect(application.is_mouse_locked);

    application.on_custom(constant.Message.lock);

    try testing.expect(!application.keyboard_blocked());
    try testing.expect(application.mouse_blocked());
}

test "a mouse lock is released like a keyboard lock" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_menu_select(constant.Menu.toggle_mouse);
    application.on_custom(constant.Message.lock);
    application.on_custom(constant.Message.unlock);

    try testing.expect(!application.keyboard_blocked());
    try testing.expect(!application.mouse_blocked());
}

test "an unknown menu identifier is ignored" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    application.on_menu_select(constant.Menu.setting + 100);

    try testing.expectEqual(State.unlocked, application.state);
}

test "a failed configuration reload keeps the running state" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    const keyboard_locked = application.is_keyboard_locked;

    application.on_custom(constant.Message.config_reload);

    try testing.expectEqual(keyboard_locked, application.is_keyboard_locked);
    try testing.expectEqual(State.unlocked, application.state);
}

test "many toggles leave the state consistent" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    var round: u32 = 0;

    while (round < 32) : (round += 1) {
        application.on_menu_select(constant.Menu.toggle);

        try testing.expectEqual(round % 2 == 0, application.state.is_locked());
    }

    try testing.expectEqual(State.unlocked, application.state);
}

const Probe = struct {
    var icon_pushed: bool = false;
    var locked_while_running: bool = false;
    var owner: ?*Application = null;
    var timer_started: bool = false;
    var tray_created: bool = false;
    var watch_registered: bool = false;

    fn reset(application: *Application) void {
        icon_pushed = false;
        locked_while_running = false;
        owner = application;
        timer_started = false;
        tray_created = false;
        watch_registered = false;
    }

    fn handle(_: *const Event, _: ?*anyopaque) Response {
        const application = owner orelse return .pass;

        tray_created = application.app.tray.is_created();
        icon_pushed = application.app.icon.get_current() != null;

        application.on_custom(constant.Message.lock);

        locked_while_running = application.keyboard_blocked();

        application.on_custom(constant.Message.unlock);

        return .pass;
    }

    fn handle_shutdown(_: *const Event, _: ?*anyopaque) Response {
        const application = owner orelse return .pass;

        timer_started = application.app.timer.is_running(constant.Timer.rehook_id);
        watch_registered = application.settings.watch_handle != null;

        return .pass;
    }
};

test "a full run creates the tray, timer, watch, and lock cycle" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    Probe.reset(&application);

    _ = application.app.bus.on(.app_init, Probe.handle, null);
    _ = application.app.bus.on(.app_shutdown, Probe.handle_shutdown, null);

    try application.run();

    try testing.expect(Probe.tray_created);
    try testing.expect(Probe.icon_pushed);
    try testing.expect(Probe.timer_started);
    try testing.expect(Probe.watch_registered);
    try testing.expect(Probe.locked_while_running);
}
