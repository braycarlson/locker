const std = @import("std");

const LockerError = @import("error.zig").LockerError;

pub const CallbackRegistry = struct {
    toggleLock: ?*const fn (bool) void = null,
    refreshHook: ?*const fn () void = null,
};

pub var registry: CallbackRegistry = .{};

pub fn setToggleLock(func: *const fn (bool) void) !void {
    registry.toggleLock = func;
}

pub fn setRefreshHook(func: *const fn () void) !void {
    registry.refreshHook = func;
}

pub fn invokeToggleLock(isLocked: bool) void {
    if (registry.toggleLock) |func| {
        func(isLocked);
    }
}

pub fn invokeRefreshHook() void {
    if (registry.refreshHook) |func| {
        func();
    }
}
