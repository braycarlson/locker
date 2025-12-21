const std = @import("std");
const w32 = @import("win32").everything;

const constant = @import("constant.zig");
const win32 = @import("win32.zig");

const Icon = @import("icon.zig").Icon;
const LockerError = @import("error.zig").LockerError;

pub const Tray = struct {
    window: w32.HWND = undefined,
    icon: Icon = .{},
    taskbarCreatedMsg: u32 = 0,
    timerActive: bool = false,

    pub fn init(self: *Tray, windowProc: w32.WNDPROC, context: *anyopaque) !void {
        self.icon.init();

        self.taskbarCreatedMsg = w32.RegisterWindowMessageW(
            win32.utf8ToUtf16("TaskbarCreated"),
        );

        const className = win32.utf8ToUtf16("Locker");

        var wndClass = std.mem.zeroes(w32.WNDCLASSEXW);
        wndClass.cbSize = @sizeOf(w32.WNDCLASSEXW);
        wndClass.lpfnWndProc = windowProc;
        wndClass.hInstance = win32.getModuleHandle();
        wndClass.lpszClassName = className;

        if (w32.RegisterClassExW(&wndClass) == 0) {
            return LockerError.WindowRegistrationFailed;
        }

        self.window = w32.CreateWindowExW(
            .{},
            className,
            className,
            .{},
            0,
            0,
            0,
            0,
            null,
            null,
            wndClass.hInstance,
            null,
        ) orelse return LockerError.WindowCreationFailed;

        _ = w32.SetWindowLongPtrW(
            self.window,
            w32.GWLP_USERDATA,
            @bitCast(@intFromPtr(context)),
        );
    }

    pub fn deinit(self: *Tray) void {
        self.removeIcon();
        _ = w32.DestroyWindow(self.window);
        self.icon.deinit();
    }

    pub fn addIcon(self: *Tray, locked: bool, tooltip: []const u8) !void {
        var data = std.mem.zeroes(w32.NOTIFYICONDATAW);
        data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
        data.hWnd = self.window;
        data.uID = 1;
        data.uFlags = .{ .MESSAGE = 1, .ICON = 1, .TIP = 1 };
        data.uCallbackMessage = constant.WM_TRAYICON;
        data.hIcon = self.icon.current(locked);

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        const text16 = try std.unicode.utf8ToUtf16LeAllocZ(arena.allocator(), tooltip);
        const limit = @min(text16.len, data.szTip.len - 1);

        for (text16[0..limit], 0..) |char, i| {
            data.szTip[i] = char;
        }

        data.szTip[limit] = 0;

        if (w32.Shell_NotifyIconW(w32.NIM_ADD, &data) == 0) {
            return LockerError.TrayIconCreationFailed;
        }
    }

    pub fn updateIcon(self: *Tray, locked: bool) void {
        var data = std.mem.zeroes(w32.NOTIFYICONDATAW);
        data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
        data.hWnd = self.window;
        data.uID = 1;
        data.uFlags = .{ .ICON = 1 };
        data.hIcon = self.icon.current(locked);

        _ = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);
    }

    pub fn removeIcon(self: *Tray) void {
        var data = std.mem.zeroes(w32.NOTIFYICONDATAW);
        data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
        data.hWnd = self.window;
        data.uID = 1;

        _ = w32.Shell_NotifyIconW(w32.NIM_DELETE, &data);
    }

    pub fn setTimer(self: *Tray) void {
        if (!self.timerActive) {
            self.timerActive = win32.setTimer(
                self.window,
                constant.Timer.REHOOK_ID,
                constant.Timer.REHOOK_INTERVAL_MS,
            );
        }
    }

    pub fn killTimer(self: *Tray) void {
        if (self.timerActive) {
            win32.killTimer(self.window, constant.Timer.REHOOK_ID);
            self.timerActive = false;
        }
    }
};
