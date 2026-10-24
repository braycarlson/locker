const std = @import("std");

const nimble = @import("nimble");

const Application = @import("application.zig").Application;
const Command = @import("menu.zig").Command;
const Config = @import("config.zig").Config;
const Message = @import("application.zig").Message;
const Remap = @import("remap.zig").Remap;
const State = @import("state.zig").State;
const TimerID = @import("application.zig").TimerID;

const Key = nimble.Key;
const Modifier = nimble.Modifier;

const testing = std.testing;

fn open(application: *Application) !void {
    nimble.mock.reset();

    try application.init(testing.io, null);
}

fn label_of(application: *const Application, command: Command) []const u8 {
    const item = application.app.menu.get_item(@backingInt(command)) orelse return "";
    return item.get_label();
}

fn post(application: *Application, message: Message) void {
    application.on_custom(.{ .code = @backingInt(message) });
}

fn select(application: *Application, command: Command) void {
    application.on_menu_select(.{ .checked = false, .id = @backingInt(command) });
}

fn tick(application: *Application, timer: TimerID) void {
    application.on_timer_tick(.{ .id = @backingInt(timer), .tick_count = 0 });
}

test "a fresh application is unlocked with nothing blocked" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    try testing.expectEqual(State.unlocked, application.state);
    try testing.expectEqualStrings("unlocked", application.app.icons.get_current_name().?);
    try testing.expectEqualStrings("Lock", label_of(&application, .toggle));
    try testing.expectEqualStrings("Exit", label_of(&application, .exit));
    try testing.expect(!application.blocked().keyboard);
    try testing.expect(!application.blocked().mouse);
    try testing.expectEqual(@as(u32, 0), application.app.notifier.sent_count());
}

test "a posted lock blocks the keyboard and updates the surface" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    post(&application, .lock);

    try testing.expectEqual(State.locked, application.state);
    try testing.expectEqualStrings("locked", application.app.icons.get_current_name().?);
    try testing.expectEqualStrings("Unlock", label_of(&application, .toggle));
    try testing.expect(application.blocked().keyboard);
    try testing.expect(!application.blocked().mouse);
    try testing.expectEqual(@as(u32, 1), application.app.notifier.sent_count());
}

test "a posted unlock releases every block" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    post(&application, .lock);
    post(&application, .unlock);

    try testing.expectEqual(State.unlocked, application.state);
    try testing.expectEqualStrings("unlocked", application.app.icons.get_current_name().?);
    try testing.expect(!application.blocked().keyboard);
    try testing.expect(!application.blocked().mouse);
    try testing.expectEqual(@as(u32, 2), application.app.notifier.sent_count());
}

test "a repeated lock is idempotent" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    post(&application, .lock);
    post(&application, .lock);

    try testing.expectEqual(State.locked, application.state);
    try testing.expectEqual(@as(u32, 1), application.app.notifier.sent_count());
}

test "an unknown custom code leaves the application alone" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    post(&application, @fromBackingInt(@backingInt(Message.unlock) + 100));

    try testing.expectEqual(State.unlocked, application.state);
    try testing.expectEqual(@as(u32, 0), application.app.notifier.sent_count());
}

test "the menu toggle drives the same transition as a posted code" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    select(&application, .toggle);

    try testing.expectEqual(State.locked, application.state);

    select(&application, .toggle);

    try testing.expectEqual(State.unlocked, application.state);
}

test "the peripheral toggles gate what a lock blocks" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    select(&application, .toggle_keyboard);

    try testing.expect(!application.peripherals.keyboard);

    select(&application, .toggle_mouse);

    try testing.expect(application.peripherals.mouse);

    post(&application, .lock);

    try testing.expect(!application.blocked().keyboard);
    try testing.expect(application.blocked().mouse);
}

test "a mouse lock is released like a keyboard lock" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    select(&application, .toggle_mouse);
    post(&application, .lock);
    post(&application, .unlock);

    try testing.expect(!application.blocked().keyboard);
    try testing.expect(!application.blocked().mouse);
}

test "an unknown menu identifier is ignored" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    select(&application, @fromBackingInt(@backingInt(Command.setting) + 100));

    try testing.expectEqual(State.unlocked, application.state);
}

test "a failed configuration reload keeps the running state" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    const peripherals = application.peripherals;

    post(&application, .config_reload);

    try testing.expectEqual(peripherals, application.peripherals);
    try testing.expectEqual(State.unlocked, application.state);
}

test "many toggles leave the state consistent" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    var round: u32 = 0;

    while (round < 32) : (round += 1) {
        select(&application, .toggle);

        try testing.expectEqual(round % 2 == 0, application.state.is_locked());
    }

    try testing.expectEqual(State.unlocked, application.state);
}

test "a rehook tick on a live connection reasserts the lock" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    tick(&application, .rehook);

    try testing.expect(application.client.is_connected());

    post(&application, .lock);

    const raw = &application.client.raw;

    try testing.expect(raw.blocked.keyboard);

    raw.blocked = .{};

    tick(&application, .rehook);

    try testing.expect(raw.blocked.keyboard);
    try testing.expect(!raw.blocked.mouse);
}

test "a remapped super shortcut sends a dummy key before it releases super" {
    nimble.mock.reset();

    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    const win = Modifier.from(.{ .win = true });

    fixture.remap[0] = .{
        .from = .{ .modifier_set = win, .value = .j },
        .to = .{ .value = .x },
    };

    fixture.remap_count = 1;

    var client = nimble.remote.Client{};

    try client.connect();
    defer client.disconnect();

    var remap = Remap.init(fixture, &client, null);

    const pressed = Key{ .value = .j, .down = true, .modifiers = win };

    try testing.expectEqual(nimble.Response.consume, remap.process(&pressed).?);

    const record = nimble.mock.record;

    try testing.expectEqual(@as(u16, 3), record.len());
    try testing.expectEqual(record.Kind.key_dummy, record.at(0).kind);
    try testing.expectEqual(record.Kind.key_up, record.at(1).kind);
    try testing.expect(record.at(1).code.is_modifier());
    try testing.expectEqual(record.Kind.key_press, record.at(2).kind);
    try testing.expectEqual(nimble.Keycode.x, record.at(2).code);
}

const Probe = struct {
    application: *Application,
    icon_pushed: bool = false,
    locked_while_running: bool = false,
    timer_started: bool = false,
    tray_created: bool = false,
    watch_registered: bool = false,

    pub fn on_app_init(probe: *Probe) void {
        const application = probe.application;

        probe.tray_created = application.app.tray.is_created();
        probe.icon_pushed = application.app.icons.get_current() != null;

        post(application, .lock);

        probe.locked_while_running = application.blocked().keyboard;

        post(application, .unlock);
    }

    pub fn on_app_shutdown(probe: *Probe) void {
        const application = probe.application;

        probe.timer_started = application.app.timers.is_running(@backingInt(TimerID.rehook));
        probe.watch_registered = application.watch != null;
    }
};

test "a full run creates the tray, timer, watch, and lock cycle" {
    var application: Application = undefined;

    try open(&application);
    defer application.deinit();

    var probe = Probe{ .application = &application };

    try application.app.bus.attach(Probe, &probe);
    try application.run();

    try testing.expectEqual(@as(u8, 8), application.app.bus.listener_count());
    try testing.expect(probe.tray_created);
    try testing.expect(probe.icon_pushed);
    try testing.expect(probe.timer_started);
    try testing.expect(probe.watch_registered);
    try testing.expect(probe.locked_while_running);
}
