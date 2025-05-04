const std = @import("std");
const w32 = @import("win32").everything;

const constants = @import("constants.zig");
const hook = @import("hook.zig");

const CircularBuffer = @import("buffer.zig").CircularBuffer;
const Logger = @import("log.zig").Logger;
const RehookTimer = @import("timer.zig").RehookTimer;
const SystemTray = @import("systemtray.zig").SystemTray;

pub const LockerState = enum {
    locked,
    unlocked,

    pub fn isLocked(self: LockerState) bool {
        return self == .locked;
    }
};

var locker: *Locker = undefined;

export fn keyboardProc(code: c_int, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.C) w32.LRESULT {
    if (code >= 0) {
        if (wparam == w32.WM_KEYDOWN or wparam == w32.WM_SYSKEYDOWN) {
            const address: usize = @intCast(lparam);
            const event: *w32.KBDLLHOOKSTRUCT = @ptrFromInt(address);

            locker.queue.push(@truncate(event.vkCode));

            if (locker.queue.isMatch(constants.Hotkey.lock) catch false) {
                locker.toggleState(.locked);
                return 1;
            }

            if (locker.queue.isMatch(constants.Hotkey.unlock) catch false) {
                locker.toggleState(.unlocked);
                return 1;
            }
        }

        if (locker.state.isLocked()) {
            const address: usize = @intCast(lparam);
            const event: *w32.KBDLLHOOKSTRUCT = @ptrFromInt(address);

            if (constants.Keyboard.isBlockedKey(event.vkCode) or
                constants.Keyboard.isBlockedMessage(wparam))
            {
                return 1;
            }
        }
    }

    return hook.callNextHookEx(code, wparam, lparam);
}

export fn mouseProc(code: c_int, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.C) w32.LRESULT {
    if (code >= 0 and locker.state.isLocked()) {
        if (constants.Mouse.isBlockedMessage(wparam)) {
            return 1;
        }
    }

    return hook.callNextHookEx(code, wparam, lparam);
}

fn onTrayToggle(isLocked: bool) void {
    locker.toggleState(if (isLocked) .locked else .unlocked);
}

fn onRefreshHook() void {
    locker.refreshHook();
}

fn setHook() bool {
    const handle = hook.getModuleHandle();

    hook.setKeyboardProc(&keyboardProc);
    hook.setMouseProc(&mouseProc);

    if (!hook.setKeyboardHook(handle)) {
        return false;
    }

    if (!hook.setMouseHook(handle)) {
        return false;
    }

    return true;
}

pub const Locker = struct {
    state: LockerState,
    queue: CircularBuffer,
    logger: Logger,
    tray: *SystemTray,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*Locker {
        var self = try allocator.create(Locker);
        errdefer allocator.destroy(self);

        self.* = Locker{
            .state = .unlocked,
            .queue = try CircularBuffer.init(allocator, 7),
            .logger = try Logger.init(allocator),
            .tray = undefined,
            .allocator = allocator,
        };

        try self.logger.open();

        self.tray = try SystemTray.init(allocator, "Peripheral Locker", self.state.isLocked());
        try self.tray.setToggleLockCallback(onTrayToggle);
        try self.tray.setRefreshHookCallback(onRefreshHook);

        self.tray.setLocked(self.state.isLocked());

        locker = self;
        return self;
    }

    pub fn deinit(self: *Locker) void {
        RehookTimer.kill(self.tray);

        self.logger.deinit();
        self.queue.deinit();
        self.tray.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn start(self: *Locker) !void {
        const handle = hook.getModuleHandle();
        hook.setKeyboardProc(&keyboardProc);

        if (!hook.setKeyboardHook(handle)) {
            try self.logger.log("Failed to set keyboard hook", .{});
        }

        _ = RehookTimer.set(self.tray);

        var message: w32.MSG = undefined;

        while (w32.GetMessageW(&message, null, 0, 0) > 0) {
            _ = w32.TranslateMessage(&message);
            _ = w32.DispatchMessageW(&message);
        }
    }

    fn refreshHook(self: *Locker) void {
        hook.removeHook();

        if (self.state.isLocked()) {
            if (!setHook()) {
                self.logError("Failed to set hooks", error.HookFailed);
            }
        } else {
            const handle = hook.getModuleHandle();
            hook.setKeyboardProc(&keyboardProc);

            if (!hook.setKeyboardHook(handle)) {
                self.logError("Failed to set keyboard hook", error.HookFailed);
            }
        }
    }

    fn toggleState(self: *Locker, state: LockerState) void {
        if (self.state == state) return;
        self.state = state;

        hook.removeHook();

        if (state.isLocked()) {
            if (!setHook()) {
                self.logError("Failed to set hooks", error.HookFailed);
            }
        } else {
            const handle = hook.getModuleHandle();
            hook.setKeyboardProc(&keyboardProc);

            if (!hook.setKeyboardHook(handle)) {
                self.logError("Failed to set keyboard hook", error.HookFailed);
            }
        }

        self.tray.setLocked(state.isLocked());
    }

    fn logError(self: *Locker, msg: []const u8, err: anyerror) void {
        self.logger.log("{s}: {}", .{ msg, err }) catch {};
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var app = try Locker.init(allocator);
    defer app.deinit();

    try app.start();
}
