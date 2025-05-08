const std = @import("std");
const w32 = @import("win32").everything;

const constants = @import("constants.zig");
const hook = @import("hook.zig");

const LockerError = @import("error.zig").LockerError;

pub const SystemTrayProc = fn (w32.HWND, u32, w32.WPARAM, w32.LPARAM) callconv(.C) w32.LRESULT;

pub const Window = struct {
    handle: w32.HWND,

    pub fn create(windowProc: SystemTrayProc) !Window {
        const name = std.unicode.utf8ToUtf16LeStringLiteral("Locker");

        var info = std.mem.zeroes(w32.WNDCLASSEXW);
        info.cbSize = @sizeOf(w32.WNDCLASSEXW);
        info.lpfnWndProc = windowProc;
        info.hInstance = hook.getModuleHandle();
        info.lpszClassName = name;

        if (w32.RegisterClassExW(&info) == 0)
            return LockerError.WindowRegistrationFailed;

        const window = w32.CreateWindowExW(.{}, name, name, .{}, 0, 0, 0, 0, null, null, info.hInstance, null) orelse return LockerError.WindowCreationFailed;

        return Window{ .handle = window };
    }

    pub fn destroy(self: *Window) void {
        _ = w32.DestroyWindow(self.handle);
        self.handle = undefined;
    }

    pub fn createTrayIcon(self: *Window, icon: w32.HICON, text: []const u8) !void {
        var data = std.mem.zeroes(w32.NOTIFYICONDATAW);
        data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
        data.hWnd = self.handle;
        data.uID = 1;
        data.uFlags = .{ .MESSAGE = 1, .ICON = 1, .TIP = 1 };
        data.uCallbackMessage = constants.WM_TRAYICON;
        data.hIcon = icon;

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        const text16 = try std.unicode.utf8ToUtf16LeAllocZ(arena.allocator(), text);
        const limit = @min(text16.len, data.szTip.len - 1);

        for (text16[0..limit], 0..) |char, i| {
            data.szTip[i] = char;
        }

        data.szTip[limit] = 0;

        if (w32.Shell_NotifyIconW(w32.NIM_ADD, &data) == 0)
            return LockerError.TrayIconCreationFailed;
    }

    pub fn updateIcon(self: *Window, icon: w32.HICON) void {
        var data = std.mem.zeroes(w32.NOTIFYICONDATAW);
        data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
        data.hWnd = self.handle;
        data.uID = 1;
        data.uFlags = .{ .ICON = 1 };
        data.hIcon = icon;

        _ = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);
    }

    pub fn removeTrayIcon(self: *Window) void {
        var data = std.mem.zeroes(w32.NOTIFYICONDATAW);
        data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
        data.hWnd = self.handle;
        data.uID = 1;

        _ = w32.Shell_NotifyIconW(w32.NIM_DELETE, &data);
    }
};
