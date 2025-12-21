const std = @import("std");
const w32 = @import("win32").everything;

pub const HookProc = *const fn (c_int, w32.WPARAM, w32.LPARAM) callconv(.c) w32.LRESULT;

pub fn getModuleHandle() w32.HINSTANCE {
    return w32.GetModuleHandleW(null) orelse @panic("Module handle not found");
}

pub fn callNextHook(code: c_int, wparam: w32.WPARAM, lparam: w32.LPARAM) w32.LRESULT {
    return w32.CallNextHookEx(null, code, wparam, lparam);
}

pub fn setWindowsHook(hookType: w32.WINDOWS_HOOK_ID, proc: HookProc, instance: w32.HINSTANCE) ?w32.HHOOK {
    return w32.SetWindowsHookExW(hookType, @ptrCast(proc), instance, 0);
}

pub fn removeWindowsHook(handle: ?w32.HHOOK) void {
    if (handle) |h| _ = w32.UnhookWindowsHookEx(h);
}

pub fn destroyIcon(handle: ?w32.HICON) void {
    if (handle) |h| _ = w32.DestroyIcon(h);
}

pub fn getCursorPosition() ?w32.POINT {
    var point: w32.POINT = undefined;
    if (w32.GetCursorPos(&point) == 0) return null;
    return point;
}

pub fn setTimer(window: w32.HWND, id: usize, interval: u32) bool {
    return w32.SetTimer(window, id, interval, null) != 0;
}

pub fn killTimer(window: w32.HWND, id: usize) void {
    _ = w32.KillTimer(window, id);
}

pub fn postQuit() void {
    _ = w32.PostQuitMessage(0);
}

pub fn utf8ToUtf16(comptime str: []const u8) [:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(str);
}
