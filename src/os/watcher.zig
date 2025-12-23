const std = @import("std");
const w32 = @import("win32").everything;

const constant = @import("../constant.zig");
const Logger = @import("../logger.zig").Logger;

const file_flag_overlapped: u32 = 0x40000000;
const buffer_size: u32 = 4096;
const path_max: u32 = 512;
const sleep_error_ns: u64 = 100 * std.time.ns_per_ms;
const sleep_debounce_ns: u64 = 50 * std.time.ns_per_ms;
const max_notification_per_batch: u32 = 64;
const name_buffer_max: u32 = 256;

const WaitResult = enum {
    io_complete,
    stop_requested,
    error_occurred,
};

pub const Watcher = struct {
    thread: ?std.Thread = null,
    handle: ?w32.HANDLE = null,
    stop_event: ?w32.HANDLE = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    callback: ?*const fn () void = null,
    logger: *?Logger,

    directory_path: [path_max]u8 = [_]u8{0} ** path_max,
    directory_path_len: u32 = 0,

    pub fn init(logger: *?Logger) Watcher {
        return .{ .logger = logger };
    }

    pub fn deinit(self: *Watcher) void {
        self.stop();

        std.debug.assert(self.thread == null);
        std.debug.assert(self.handle == null);
        std.debug.assert(self.stop_event == null);
        std.debug.assert(self.running.load(.acquire) == false);
    }

    fn closeDirectoryHandle(self: *Watcher) void {
        if (self.handle) |handle| {
            _ = w32.CloseHandle(handle);
            self.handle = null;
        }

        std.debug.assert(self.handle == null);
    }

    fn closeStopEvent(self: *Watcher) void {
        if (self.stop_event) |event| {
            _ = w32.CloseHandle(event);
            self.stop_event = null;
        }

        std.debug.assert(self.stop_event == null);
    }

    fn createStopEvent(self: *Watcher) !void {
        std.debug.assert(self.stop_event == null);

        self.stop_event = w32.CreateEventW(null, w32.TRUE, w32.FALSE, null);

        if (self.stop_event == null) {
            if (self.logger.*) |*l| {
                l.log("Failed to create stop event", .{});
            }

            return error.EventCreationFailed;
        }

        std.debug.assert(self.stop_event != null);
    }

    fn handleNotification(self: *Watcher, info: *const w32.FILE_NOTIFY_INFORMATION, name_len: u32) void {
        std.debug.assert(name_len > 0);

        const name_slice = @as([*]const u16, &info.FileName)[0..name_len];

        var name_buf: [name_buffer_max]u8 = undefined;

        const utf8_len = std.unicode.utf16LeToUtf8(&name_buf, name_slice) catch 0;

        if (utf8_len == 0) {
            return;
        }

        std.debug.assert(utf8_len > 0);
        std.debug.assert(utf8_len <= name_buffer_max);

        const file_name = name_buf[0..utf8_len];

        const is_config = std.mem.eql(u8, file_name, "config.zon");

        if (!is_config) {
            return;
        }

        std.debug.assert(is_config);

        if (self.logger.*) |*l| {
            l.log("Config file was modified", .{});
        }

        std.Thread.sleep(sleep_debounce_ns);

        if (self.callback) |cb| {
            cb();
        }
    }

    fn openDirectoryHandle(self: *Watcher) !void {
        std.debug.assert(self.handle == null);
        std.debug.assert(self.directory_path_len > 0);
        std.debug.assert(self.directory_path_len <= path_max);

        var wide_dir: [path_max]u16 = undefined;
        const directory = self.directory_path[0..self.directory_path_len];

        const len = std.unicode.utf8ToUtf16Le(&wide_dir, directory) catch {
            return error.InvalidPath;
        };

        if (len == 0) {
            return error.InvalidPath;
        }

        std.debug.assert(len > 0);
        std.debug.assert(len < path_max);

        wide_dir[len] = 0;

        self.handle = w32.CreateFileW(
            @ptrCast(&wide_dir),
            @bitCast(constant.File.list_directory),
            .{ .READ = 1, .WRITE = 1, .DELETE = 1 },
            null,
            w32.OPEN_EXISTING,
            @bitCast(constant.File.flag_backup_semantics | file_flag_overlapped),
            null,
        );

        if (self.handle == w32.INVALID_HANDLE_VALUE) {
            if (self.logger.*) |*l| {
                l.log("Failed to open directory for watching", .{});
            }

            self.handle = null;
            return error.WatchFailed;
        }

        std.debug.assert(self.handle != null);
        std.debug.assert(self.handle != w32.INVALID_HANDLE_VALUE);
    }

    fn processNotifications(self: *Watcher, buffer: *[buffer_size]u8, bytes_returned: u32) void {
        std.debug.assert(bytes_returned > 0);
        std.debug.assert(bytes_returned <= buffer_size);

        if (bytes_returned == 0) {
            return;
        }

        if (bytes_returned > buffer_size) {
            return;
        }

        var offset: u32 = 0;
        var iteration: u32 = 0;

        while (iteration < max_notification_per_batch) {
            std.debug.assert(iteration < max_notification_per_batch);

            if (offset >= buffer_size) {
                break;
            }

            std.debug.assert(offset < buffer_size);

            const info: *const w32.FILE_NOTIFY_INFORMATION = @ptrCast(@alignCast(&buffer[offset]));
            const name_len = info.FileNameLength / 2;

            if (name_len == 0) {
                break;
            }

            std.debug.assert(name_len > 0);

            self.handleNotification(info, name_len);

            if (info.NextEntryOffset == 0) {
                break;
            }

            offset += info.NextEntryOffset;
            iteration += 1;
        }

        std.debug.assert(iteration <= max_notification_per_batch);
    }

    fn setupDirectoryPath(self: *Watcher, path: []const u8) !void {
        std.debug.assert(path.len > 0);
        std.debug.assert(path.len <= path_max);

        const directory = std.fs.path.dirname(path) orelse {
            return error.InvalidPath;
        };

        if (directory.len == 0) {
            return error.InvalidPath;
        }

        if (directory.len > path_max) {
            return error.PathTooLong;
        }

        std.debug.assert(directory.len > 0);
        std.debug.assert(directory.len <= path_max);
        std.debug.assert(directory.len < path.len);

        @memcpy(self.directory_path[0..directory.len], directory);
        self.directory_path_len = @intCast(directory.len);

        std.debug.assert(self.directory_path_len > 0);
        std.debug.assert(self.directory_path_len <= path_max);
        std.debug.assert(self.directory_path_len == directory.len);
    }

    fn waitForNotification(
        self: *Watcher,
        handle: w32.HANDLE,
        stop_event: w32.HANDLE,
        io_event: w32.HANDLE,
        buffer: *[buffer_size]u8,
        overlapped: *w32.OVERLAPPED,
    ) WaitResult {
        std.debug.assert(handle != w32.INVALID_HANDLE_VALUE);

        _ = w32.ResetEvent(io_event);

        const result = w32.ReadDirectoryChangesW(
            handle,
            buffer,
            buffer.len,
            w32.FALSE,
            .{ .LAST_WRITE = 1 },
            null,
            overlapped,
            null,
        );

        if (result == 0) {
            const err = w32.GetLastError();

            if (err != w32.WIN32_ERROR.ERROR_IO_PENDING) {
                if (!self.running.load(.acquire)) {
                    return .stop_requested;
                }

                return .error_occurred;
            }
        }

        const handles = [_]w32.HANDLE{ io_event, stop_event };
        const wait_result = w32.WaitForMultipleObjects(2, &handles, w32.FALSE, w32.INFINITE);
        const object_0 = @intFromEnum(w32.WAIT_OBJECT_0);

        if (wait_result == object_0 + 1) {
            _ = w32.CancelIo(handle);
            return .stop_requested;
        }

        if (wait_result != object_0) {
            if (!self.running.load(.acquire)) {
                return .stop_requested;
            }

            return .error_occurred;
        }

        std.debug.assert(wait_result == object_0);

        return .io_complete;
    }

    pub fn start(self: *Watcher, path: []const u8, callback: *const fn () void) !void {
        std.debug.assert(path.len > 0);
        std.debug.assert(path.len <= path_max);

        if (path.len == 0) {
            return error.InvalidPath;
        }

        if (path.len > path_max) {
            return error.PathTooLong;
        }

        if (self.running.load(.acquire)) {
            return;
        }

        std.debug.assert(!self.running.load(.acquire));

        self.callback = callback;

        std.debug.assert(self.callback != null);

        try self.setupDirectoryPath(path);
        try self.createStopEvent();

        errdefer self.closeStopEvent();

        try self.openDirectoryHandle();

        errdefer self.closeDirectoryHandle();

        self.running.store(true, .release);

        std.debug.assert(self.running.load(.acquire));

        self.thread = std.Thread.spawn(.{}, watchLoop, .{self}) catch |err| {
            if (self.logger.*) |*l| {
                l.log("Failed to spawn watcher thread: {}", .{err});
            }

            self.closeDirectoryHandle();
            self.closeStopEvent();
            self.running.store(false, .release);

            return error.ThreadSpawnFailed;
        };

        std.debug.assert(self.thread != null);
        std.debug.assert(self.running.load(.acquire) == true);
    }

    pub fn stop(self: *Watcher) void {
        if (!self.running.load(.acquire)) {
            return;
        }

        std.debug.assert(self.running.load(.acquire));

        self.running.store(false, .release);

        if (self.stop_event) |event| {
            _ = w32.SetEvent(event);
        }

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        self.closeDirectoryHandle();
        self.closeStopEvent();

        std.debug.assert(self.thread == null);
        std.debug.assert(self.handle == null);
        std.debug.assert(self.stop_event == null);
        std.debug.assert(!self.running.load(.acquire));
    }
};

fn watchLoop(self: *Watcher) void {
    std.debug.assert(self.running.load(.acquire));

    if (self.logger.*) |*l| {
        l.log("Started watching for config changes", .{});
    }

    var buffer: [buffer_size]u8 align(@alignOf(w32.FILE_NOTIFY_INFORMATION)) = undefined;
    var overlapped: w32.OVERLAPPED = std.mem.zeroes(w32.OVERLAPPED);

    overlapped.hEvent = w32.CreateEventW(null, w32.TRUE, w32.FALSE, null);

    if (overlapped.hEvent == null) {
        return;
    }

    defer _ = w32.CloseHandle(overlapped.hEvent);

    var iteration: u64 = 0;
    const iteration_max: u64 = std.math.maxInt(u64);

    while (self.running.load(.acquire)) {
        std.debug.assert(iteration < iteration_max);

        const handle = self.handle orelse break;
        const stop_event = self.stop_event orelse break;
        const io_event = overlapped.hEvent orelse break;

        const wait_result = self.waitForNotification(
            handle,
            stop_event,
            io_event,
            &buffer,
            &overlapped,
        );

        if (wait_result == .stop_requested) {
            break;
        }

        if (wait_result == .error_occurred) {
            std.Thread.sleep(sleep_error_ns);
            iteration += 1;

            continue;
        }

        std.debug.assert(wait_result == .io_complete);

        var bytes_returned: u32 = 0;

        const overlapped_result = w32.GetOverlappedResult(handle, &overlapped, &bytes_returned, w32.FALSE);

        if (overlapped_result == 0) {
            iteration += 1;
            continue;
        }

        if (bytes_returned == 0) {
            iteration += 1;
            continue;
        }

        if (bytes_returned > buffer_size) {
            iteration += 1;
            continue;
        }

        std.debug.assert(bytes_returned > 0);
        std.debug.assert(bytes_returned <= buffer_size);

        self.processNotifications(&buffer, bytes_returned);

        iteration += 1;
    }

    if (self.logger.*) |*l| {
        l.log("Stopped watching for config changes", .{});
    }
}
