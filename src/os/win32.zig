const std = @import("std");
const w32 = @import("win32").everything;

const path_max: u32 = 512;

pub const HookProc = *const fn (c_int, w32.WPARAM, w32.LPARAM) callconv(.c) w32.LRESULT;

pub fn callNextHook(code: c_int, wparam: w32.WPARAM, lparam: w32.LPARAM) w32.LRESULT {
    return w32.CallNextHookEx(null, code, wparam, lparam);
}

pub fn convertStringToWide(source: []const u8, dest: []u16) usize {
    std.debug.assert(source.len > 0);
    std.debug.assert(dest.len > 0);

    const len = std.unicode.utf8ToUtf16Le(dest, source) catch return 0;
    return len;
}

pub fn copyToWideBuffer(dest: anytype, source: anytype, source_len: usize) void {
    std.debug.assert(source_len > 0);

    const dest_len: u32 = @intCast(dest.len);
    const src_len: u32 = @intCast(source_len);

    std.debug.assert(dest_len > 0);
    std.debug.assert(src_len > 0);

    const limit = @min(src_len, dest_len - 1);

    std.debug.assert(limit > 0);
    std.debug.assert(limit < dest_len);

    var index: u32 = 0;

    while (index < limit) : (index += 1) {
        std.debug.assert(index < dest_len);
        std.debug.assert(index < limit);

        dest[index] = source[index];
    }

    std.debug.assert(index == limit);

    dest[limit] = 0;
}

pub fn destroyIcon(handle: ?w32.HICON) void {
    if (handle) |h| {
        _ = w32.DestroyIcon(h);
    }
}

pub fn getCursorPosition() ?w32.POINT {
    var point: w32.POINT = undefined;

    const result = w32.GetCursorPos(&point);

    if (result == 0) {
        return null;
    }

    std.debug.assert(result != 0);

    return point;
}

pub fn getModuleHandle() w32.HINSTANCE {
    const handle = w32.GetModuleHandleW(null);

    if (handle == null) {
        @panic("Module handle not found");
    }

    std.debug.assert(handle != null);

    return handle.?;
}

pub fn killTimer(window: w32.HWND, id: usize) void {
    std.debug.assert(id > 0);

    _ = w32.KillTimer(window, id);
}

pub fn postQuit() void {
    w32.PostQuitMessage(0);
}

pub fn removeWindowsHook(handle: ?w32.HHOOK) void {
    if (handle) |h| {
        _ = w32.UnhookWindowsHookEx(h);
    }
}

pub fn setTimer(window: w32.HWND, id: usize, interval_ms: u32) bool {
    std.debug.assert(id > 0);
    std.debug.assert(interval_ms > 0);

    const result = w32.SetTimer(window, id, interval_ms, null);

    if (result != 0) {
        return true;
    }

    return false;
}

pub fn setWindowsHook(hook_type: w32.WINDOWS_HOOK_ID, proc: HookProc, instance: w32.HINSTANCE) ?w32.HHOOK {
    return w32.SetWindowsHookExW(hook_type, @ptrCast(proc), instance, 0);
}

pub fn shellOpen(path: []const u8) void {
    const path_len: u32 = @intCast(path.len);

    if (path_len == 0) {
        return;
    }

    if (path_len > path_max) {
        return;
    }

    std.debug.assert(path_len > 0);
    std.debug.assert(path_len <= path_max);

    var wide_buf: [path_max]u16 = undefined;

    const len = std.unicode.utf8ToUtf16Le(&wide_buf, path) catch return;
    const len_u32: u32 = @intCast(len);

    if (len_u32 == 0) {
        return;
    }

    if (len_u32 >= path_max) {
        return;
    }

    std.debug.assert(len_u32 > 0);
    std.debug.assert(len_u32 < path_max);

    wide_buf[len_u32] = 0;

    _ = w32.ShellExecuteW(
        null,
        utf8ToUtf16("open"),
        @ptrCast(&wide_buf),
        null,
        null,
        1,
    );
}

pub fn utf8ToUtf16(comptime str: []const u8) [:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(str);
}
