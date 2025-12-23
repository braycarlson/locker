const std = @import("std");
const w32 = @import("win32").everything;

const constant = @import("../constant.zig");
const win32 = @import("../os/win32.zig");

const Icon = @import("icon.zig").Icon;
const LockerError = @import("../error.zig").LockerError;

const tooltip_max: u32 = 128;
const title_max: u32 = 64;
const message_max: u32 = 256;

pub const Tray = struct {
    window: ?w32.HWND = null,
    icon: Icon = .{},
    taskbar_created_msg: u32 = 0,
    is_timer_active: bool = false,

    pub fn init(self: *Tray, window_proc: w32.WNDPROC, context: *anyopaque) !void {
        std.debug.assert(self.taskbar_created_msg == 0);
        std.debug.assert(!self.is_timer_active);

        self.icon.init();

        self.taskbar_created_msg = w32.RegisterWindowMessageW(
            win32.utf8ToUtf16("TaskbarCreated"),
        );

        std.debug.assert(self.taskbar_created_msg > 0);

        const class_name = win32.utf8ToUtf16("Locker");

        var wnd_class = std.mem.zeroes(w32.WNDCLASSEXW);
        wnd_class.cbSize = @sizeOf(w32.WNDCLASSEXW);
        wnd_class.lpfnWndProc = window_proc;
        wnd_class.hInstance = win32.getModuleHandle();
        wnd_class.lpszClassName = class_name;

        const class_result = w32.RegisterClassExW(&wnd_class);

        if (class_result == 0) {
            return LockerError.WindowRegistrationFailed;
        }

        std.debug.assert(class_result != 0);

        self.window = w32.CreateWindowExW(
            .{},
            class_name,
            class_name,
            .{},
            0,
            0,
            0,
            0,
            null,
            null,
            wnd_class.hInstance,
            null,
        );

        if (self.window == null) {
            return LockerError.WindowCreationFailed;
        }

        _ = w32.SetWindowLongPtrW(
            self.window.?,
            w32.GWLP_USERDATA,
            @bitCast(@intFromPtr(context)),
        );

        std.debug.assert(self.taskbar_created_msg > 0);
    }

    pub fn deinit(self: *Tray) void {
        std.debug.assert(self.taskbar_created_msg > 0);

        self.removeIcon();

        if (self.window) |window| {
            _ = w32.DestroyWindow(window);
        }

        self.icon.deinit();

        std.debug.assert(!self.is_timer_active);
    }

    fn convertTooltipToWide(tooltip: []const u8, wide_buf: *[tooltip_max]u16) !usize {
        std.debug.assert(tooltip.len > 0);

        const len = win32.convertStringToWide(tooltip, wide_buf);

        if (len == 0) {
            return LockerError.InvalidCapacity;
        }

        std.debug.assert(len > 0);
        std.debug.assert(len <= tooltip_max);

        return len;
    }

    fn createBaseIconData(self: *Tray) w32.NOTIFYICONDATAW {
        var data = std.mem.zeroes(w32.NOTIFYICONDATAW);
        data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
        data.hWnd = self.window.?;
        data.uID = 1;

        return data;
    }

    fn createIconData(self: *Tray, locked: bool) w32.NOTIFYICONDATAW {
        var data = self.createBaseIconData();
        data.uFlags = .{ .MESSAGE = 1, .ICON = 1, .TIP = 1 };
        data.uCallbackMessage = constant.wm_trayicon;
        data.hIcon = self.icon.current(locked);

        return data;
    }

    fn setTooltip(data: *w32.NOTIFYICONDATAW, wide_buf: *[tooltip_max]u16, len: usize) void {
        std.debug.assert(len > 0);
        std.debug.assert(len <= tooltip_max);

        const tip_len: u32 = @intCast(data.szTip.len);
        const len_u32: u32 = @intCast(len);
        const limit = @min(len_u32, tip_len - 1);

        std.debug.assert(limit > 0);
        std.debug.assert(limit < tip_len);

        var index: u32 = 0;

        while (index < limit) : (index += 1) {
            std.debug.assert(index < tip_len);
            std.debug.assert(index < limit);

            data.szTip[index] = wide_buf[index];
        }

        std.debug.assert(index == limit);

        data.szTip[limit] = 0;
    }

    pub fn addIcon(self: *Tray, locked: bool, tooltip: []const u8) !void {
        const tooltip_len: u32 = @intCast(tooltip.len);

        if (tooltip_len == 0) {
            return LockerError.InvalidCapacity;
        }

        std.debug.assert(tooltip_len > 0);

        var data = self.createIconData(locked);

        var wide_buf: [tooltip_max]u16 = undefined;
        const len = try convertTooltipToWide(tooltip, &wide_buf);

        win32.copyToWideBuffer(&data.szTip, &wide_buf, len);

        const result = w32.Shell_NotifyIconW(w32.NIM_ADD, &data);

        if (result == 0) {
            return LockerError.TrayIconCreationFailed;
        }

        std.debug.assert(result != 0);
    }

    pub fn killTimer(self: *Tray) void {
        if (!self.is_timer_active) {
            return;
        }

        std.debug.assert(self.is_timer_active);

        if (self.window) |window| {
            win32.killTimer(window, constant.Timer.rehook_id);
        }

        self.is_timer_active = false;

        std.debug.assert(!self.is_timer_active);
    }

    pub fn removeIcon(self: *Tray) void {
        std.debug.assert(self.taskbar_created_msg > 0);

        var data = self.createBaseIconData();

        _ = w32.Shell_NotifyIconW(w32.NIM_DELETE, &data);
    }

    pub fn setTimer(self: *Tray) void {
        std.debug.assert(!self.is_timer_active);

        if (self.is_timer_active) {
            return;
        }

        if (self.window) |window| {
            self.is_timer_active = win32.setTimer(
                window,
                constant.Timer.rehook_id,
                constant.Timer.rehook_interval_ms,
            );
        }
    }

    fn setNotificationStrings(data: *w32.NOTIFYICONDATAW, title_buf: *[title_max]u16, title_len: usize, message_buf: *[message_max]u16, message_len: usize) void {
        std.debug.assert(title_len > 0);
        std.debug.assert(message_len > 0);

        win32.copyToWideBuffer(&data.szInfoTitle, title_buf, title_len);
        win32.copyToWideBuffer(&data.szInfo, message_buf, message_len);
    }

    pub fn showNotification(self: *Tray, title: []const u8, message: []const u8) void {
        const title_len: u32 = @intCast(title.len);
        const message_len: u32 = @intCast(message.len);

        if (title_len == 0) {
            return;
        }

        if (message_len == 0) {
            return;
        }

        std.debug.assert(title_len > 0);
        std.debug.assert(message_len > 0);

        var title_buf: [title_max]u16 = undefined;
        var message_buf: [message_max]u16 = undefined;

        const title_conv_len = win32.convertStringToWide(title, &title_buf);
        const message_conv_len = win32.convertStringToWide(message, &message_buf);

        if (title_conv_len == 0) {
            return;
        }

        if (message_conv_len == 0) {
            return;
        }

        std.debug.assert(title_conv_len > 0);
        std.debug.assert(title_conv_len <= title_max);
        std.debug.assert(message_conv_len > 0);
        std.debug.assert(message_conv_len <= message_max);

        var data = self.createBaseIconData();
        data.uFlags = .{ .INFO = 1 };

        setNotificationStrings(&data, &title_buf, title_conv_len, &message_buf, message_conv_len);

        _ = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);
    }

    pub fn updateIcon(self: *Tray, locked: bool) void {
        std.debug.assert(self.taskbar_created_msg > 0);

        var data = self.createBaseIconData();
        data.uFlags = .{ .ICON = 1 };
        data.hIcon = self.icon.current(locked);

        _ = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);
    }
};

fn copyToBuffer(dest: anytype, source: anytype, source_len: usize) void {
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
