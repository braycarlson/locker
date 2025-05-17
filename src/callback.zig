const std = @import("std");

const LockerError = @import("error.zig").LockerError;

pub const CallbackRegistry = struct {
    toggleLock: ?*const fn (bool) void = null,
    refreshHook: ?*const fn () void = null,
    setKeyboardLocked: ?*const fn (bool) void = null,
    setMouseLocked: ?*const fn (bool) void = null,
    isKeyboardLocked: ?*const fn () bool = null,
    isMouseLocked: ?*const fn () bool = null,
};

pub var registry: CallbackRegistry = .{};

pub fn setKeyboardLockedCallback(func: *const fn (bool) void) !void {
    registry.setKeyboardLocked = func;
}

pub fn setMouseLockedCallback(func: *const fn (bool) void) !void {
    registry.setMouseLocked = func;
}

pub fn setIsKeyboardLockedCallback(func: *const fn () bool) !void {
    registry.isKeyboardLocked = func;
}

pub fn setIsMouseLockedCallback(func: *const fn () bool) !void {
    registry.isMouseLocked = func;
}

pub fn invokeSetKeyboardLocked(locked: bool) void {
    if (registry.setKeyboardLocked) |func| {
        func(locked);
    }
}

pub fn invokeSetMouseLocked(locked: bool) void {
    if (registry.setMouseLocked) |func| {
        func(locked);
    }
}

pub fn invokeIsKeyboardLocked() bool {
    if (registry.isKeyboardLocked) |func| {
        return func();
    }

    return true;
}

pub fn invokeIsMouseLocked() bool {
    if (registry.isMouseLocked) |func| {
        return func();
    }

    return true;
}

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
