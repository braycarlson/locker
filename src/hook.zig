const std = @import("std");
const w32 = @import("win32").everything;

const LockerError = @import("error.zig").LockerError;

pub const HookProc = fn (c_int, w32.WPARAM, w32.LPARAM) callconv(.C) w32.LRESULT;

pub export var hKeyboardHook: ?w32.HHOOK = null;
pub export var hMouseHook: ?w32.HHOOK = null;

var keyboardProcPtr: ?*const HookProc = null;
var mouseProcPtr: ?*const HookProc = null;

fn _setHook(
    hookType: w32.WINDOWS_HOOK_ID,
    hookProc: *const HookProc,
    hInstance: w32.HINSTANCE,
    threadId: u32,
) !void {
    const hook_handle = w32.SetWindowsHookExW(
        hookType,
        @ptrCast(hookProc),
        hInstance,
        threadId,
    );

    if (hook_handle == null) return LockerError.HookFailed;

    switch (hookType) {
        w32.WH_KEYBOARD_LL => hKeyboardHook = hook_handle,
        w32.WH_MOUSE_LL => hMouseHook = hook_handle,
        else => std.debug.panic("Unsupported hook type", .{}),
    }
}

pub export fn callNextHookEx(nCode: c_int, wParam: w32.WPARAM, lParam: w32.LPARAM) w32.LRESULT {
    return w32.CallNextHookEx(null, nCode, wParam, lParam);
}

pub export fn getModuleHandle() w32.HINSTANCE {
    const handle = w32.GetModuleHandleW(null);

    if (handle == null) {
        std.debug.print("Failed to get module handle\n", .{});
        @panic("Module handle not found");
    }

    return handle.?;
}

pub export fn removeHook() void {
    if (hKeyboardHook) |h| {
        _ = w32.UnhookWindowsHookEx(h);
        hKeyboardHook = null;
    }

    if (hMouseHook) |h| {
        _ = w32.UnhookWindowsHookEx(h);
        hMouseHook = null;
    }
}

pub export fn setKeyboardHook(hInstance: w32.HINSTANCE) bool {
    if (keyboardProcPtr) |proc| {
        _setHook(w32.WH_KEYBOARD_LL, proc, hInstance, 0) catch {
            return false;
        };

        return true;
    }

    return false;
}

pub export fn setKeyboardProc(proc: *const HookProc) void {
    keyboardProcPtr = proc;
}

pub export fn setMouseHook(hInstance: w32.HINSTANCE) bool {
    if (mouseProcPtr) |proc| {
        _setHook(w32.WH_MOUSE_LL, proc, hInstance, 0) catch {
            return false;
        };

        return true;
    }

    return false;
}

pub export fn setMouseProc(proc: *const HookProc) void {
    mouseProcPtr = proc;
}

pub export fn setHook(
    hookType: w32.WINDOWS_HOOK_ID,
    hookProc: *const HookProc,
    hInstance: w32.HINSTANCE,
    threadId: u32,
) bool {
    _setHook(hookType, hookProc, hInstance, threadId) catch {
        return false;
    };

    return true;
}
