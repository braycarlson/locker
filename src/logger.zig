const std = @import("std");

pub const RotationPolicy = union(enum) {
    size: usize,
    daily: void,
    both: usize,
};

pub const Logger = struct {
    const buffer_size: u32 = 4096;
    const backup_max: u32 = 5;
    const path_max: u32 = 512;

    file: ?std.fs.File = null,
    path: [path_max]u8 = [_]u8{0} ** path_max,
    path_len: u32 = 0,
    mutex: std.Thread.Mutex = .{},
    policy: RotationPolicy,
    current_size: u32 = 0,
    last_date: ?Date = null,
    write_errors: u32 = 0,

    const Date = struct {
        year: u16,
        month: u4,
        day: u5,

        fn eql(self: Date, other: Date) bool {
            std.debug.assert(self.year > 0);
            std.debug.assert(other.year > 0);
            std.debug.assert(self.month >= 1);
            std.debug.assert(self.month <= 12);
            std.debug.assert(other.month >= 1);
            std.debug.assert(other.month <= 12);
            std.debug.assert(self.day >= 1);
            std.debug.assert(self.day <= 31);
            std.debug.assert(other.day >= 1);
            std.debug.assert(other.day <= 31);

            if (self.year != other.year) {
                return false;
            }

            if (self.month != other.month) {
                return false;
            }

            if (self.day != other.day) {
                return false;
            }

            return true;
        }
    };

    pub fn init(path: []const u8, policy: RotationPolicy) !Logger {
        const path_len: u32 = @intCast(path.len);

        if (path_len == 0) {
            return error.InvalidPath;
        }

        if (path_len > path_max) {
            return error.PathTooLong;
        }

        std.debug.assert(path_len > 0);
        std.debug.assert(path_len <= path_max);

        var self = Logger{ .policy = policy };

        @memcpy(self.path[0..path_len], path);
        self.path_len = path_len;

        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);
        std.debug.assert(self.path_len == path_len);

        try self.openFile();

        std.debug.assert(self.file != null);
        std.debug.assert(self.last_date != null);

        return self;
    }

    pub fn deinit(self: *Logger) void {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);

        if (self.file) |file| {
            file.close();
            self.file = null;
        }

        std.debug.assert(self.file == null);
    }

    fn getCurrentDate(self: *Logger) Date {
        _ = self;

        const timestamp = std.time.timestamp();

        std.debug.assert(timestamp >= 0);

        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = datetime.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        const result = Date{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
        };

        std.debug.assert(result.year > 0);
        std.debug.assert(result.month >= 1);
        std.debug.assert(result.month <= 12);
        std.debug.assert(result.day >= 1);
        std.debug.assert(result.day <= 31);

        return result;
    }

    fn getPathSlice(self: *Logger) []const u8 {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);

        return self.path[0..self.path_len];
    }

    fn hasDateChanged(self: *Logger) bool {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);

        const current = self.getCurrentDate();
        const last = self.last_date orelse return false;

        std.debug.assert(current.year > 0);
        std.debug.assert(last.year > 0);

        if (current.eql(last)) {
            return false;
        }

        return true;
    }

    fn openFile(self: *Logger) !void {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);
        std.debug.assert(self.file == null);

        const path = self.getPathSlice();
        const directory = std.fs.path.dirname(path) orelse return error.InvalidPath;

        std.debug.assert(directory.len > 0);
        std.debug.assert(directory.len < path.len);

        std.fs.makeDirAbsolute(directory) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };

        self.file = try std.fs.createFileAbsolute(path, .{ .read = true, .truncate = false });

        std.debug.assert(self.file != null);

        const stat = try self.file.?.stat();
        self.current_size = @intCast(stat.size);

        try self.file.?.seekFromEnd(0);

        self.last_date = self.getCurrentDate();

        std.debug.assert(self.file != null);
        std.debug.assert(self.last_date != null);
    }

    fn rotate(self: *Logger) !void {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);

        if (self.file) |file| {
            file.close();
            self.file = null;
        }

        std.debug.assert(self.file == null);

        try self.rotateFiles();
        try self.openFile();

        self.current_size = 0;
        self.last_date = self.getCurrentDate();

        std.debug.assert(self.file != null);
        std.debug.assert(self.last_date != null);
        std.debug.assert(self.current_size == 0);
    }

    fn rotateFiles(self: *Logger) !void {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);

        const path = self.getPathSlice();

        var old_path_buf: [path_max + 8]u8 = undefined;
        var new_path_buf: [path_max + 8]u8 = undefined;

        var i: u32 = backup_max;
        var iteration: u32 = 0;

        while (i > 0) : (i -= 1) {
            std.debug.assert(iteration < backup_max);

            var old_path: []const u8 = undefined;

            if (i == 1) {
                old_path = path;
            } else {
                old_path = std.fmt.bufPrint(&old_path_buf, "{s}.{d}", .{ path, i - 1 }) catch continue;
            }

            const new_path = std.fmt.bufPrint(&new_path_buf, "{s}.{d}", .{ path, i }) catch continue;

            std.debug.assert(old_path.len > 0);
            std.debug.assert(new_path.len > 0);

            if (i == backup_max) {
                std.fs.deleteFileAbsolute(new_path) catch |err| {
                    if (err != error.FileNotFound) {
                        self.write_errors += 1;
                    }
                };
            }

            std.fs.renameAbsolute(old_path, new_path) catch |err| {
                if (err != error.FileNotFound) {
                    self.write_errors += 1;
                }
            };

            iteration += 1;
        }

        std.debug.assert(iteration <= backup_max);
    }

    fn shouldRotate(self: *Logger) bool {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);

        switch (self.policy) {
            .size => |max_size| {
                if (self.current_size >= max_size) {
                    return true;
                }

                return false;
            },
            .daily => {
                return self.hasDateChanged();
            },
            .both => |max_size| {
                if (self.current_size >= max_size) {
                    return true;
                }

                if (self.hasDateChanged()) {
                    return true;
                }

                return false;
            },
        }
    }

    fn writeTimestamp(self: *Logger, writer: anytype) !void {
        _ = self;

        const timestamp = std.time.timestamp();

        std.debug.assert(timestamp >= 0);

        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = datetime.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = datetime.getDaySeconds();

        std.debug.assert(year_day.year > 0);

        const hours = day_seconds.getHoursIntoDay();
        const minutes = day_seconds.getMinutesIntoHour();
        const seconds = day_seconds.getSecondsIntoMinute();

        std.debug.assert(hours < 24);
        std.debug.assert(minutes < 60);
        std.debug.assert(seconds < 60);

        try writer.print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            hours,
            minutes,
            seconds,
        });
    }

    fn ensureFileReady(self: *Logger) bool {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);

        if (self.shouldRotate()) {
            self.rotate() catch {
                self.write_errors += 1;
                return false;
            };
        }

        if (self.file == null) {
            self.write_errors += 1;
            return false;
        }

        return true;
    }

    fn formatMessage(self: *Logger, buffer: *[buffer_size]u8, comptime fmt: []const u8, args: anytype) ?[]const u8 {
        var fbs = std.io.fixedBufferStream(buffer);
        const writer = fbs.writer();

        self.writeTimestamp(writer) catch {
            self.write_errors += 1;
            return null;
        };

        writer.print(fmt ++ "\n", args) catch {
            self.write_errors += 1;
            return null;
        };

        return fbs.getWritten();
    }

    fn writeToFile(self: *Logger, written: []const u8) void {
        std.debug.assert(written.len > 0);
        std.debug.assert(written.len <= buffer_size);

        const file = self.file orelse return;
        const written_len: u32 = @intCast(written.len);

        const bytes_written = file.write(written) catch {
            self.write_errors += 1;
            return;
        };

        if (bytes_written != written.len) {
            self.write_errors += 1;
        }

        file.sync() catch {
            self.write_errors += 1;
        };

        self.current_size += written_len;
    }

    pub fn log(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.mutex.lock();

        defer self.mutex.unlock();

        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_max);

        if (!self.ensureFileReady()) {
            return;
        }

        var buffer: [buffer_size]u8 = undefined;

        const written = self.formatMessage(&buffer, fmt, args) orelse return;

        self.writeToFile(written);
    }
};

const testing = std.testing;

test "Logger.Date.eql with identical dates" {
    const date1 = Logger.Date{ .year = 2024, .month = 6, .day = 15 };
    const date2 = Logger.Date{ .year = 2024, .month = 6, .day = 15 };

    try testing.expect(date1.eql(date2));
    try testing.expect(date2.eql(date1));
}

test "Logger.Date.eql with different years" {
    const date1 = Logger.Date{ .year = 2024, .month = 6, .day = 15 };
    const date2 = Logger.Date{ .year = 2025, .month = 6, .day = 15 };

    try testing.expect(!date1.eql(date2));
    try testing.expect(!date2.eql(date1));
}

test "Logger.Date.eql with different months" {
    const date1 = Logger.Date{ .year = 2024, .month = 6, .day = 15 };
    const date2 = Logger.Date{ .year = 2024, .month = 7, .day = 15 };

    try testing.expect(!date1.eql(date2));
    try testing.expect(!date2.eql(date1));
}

test "Logger.Date.eql with different days" {
    const date1 = Logger.Date{ .year = 2024, .month = 6, .day = 15 };
    const date2 = Logger.Date{ .year = 2024, .month = 6, .day = 16 };

    try testing.expect(!date1.eql(date2));
    try testing.expect(!date2.eql(date1));
}

test "Logger.Date.eql with all different" {
    const date1 = Logger.Date{ .year = 2024, .month = 6, .day = 15 };
    const date2 = Logger.Date{ .year = 2025, .month = 7, .day = 16 };

    try testing.expect(!date1.eql(date2));
    try testing.expect(!date2.eql(date1));
}

test "Logger.Date.eql with boundary values" {
    const date1 = Logger.Date{ .year = 2024, .month = 1, .day = 1 };
    const date2 = Logger.Date{ .year = 2024, .month = 1, .day = 1 };

    try testing.expect(date1.eql(date2));
}

test "Logger.Date.eql with end of year" {
    const date1 = Logger.Date{ .year = 2024, .month = 12, .day = 31 };
    const date2 = Logger.Date{ .year = 2024, .month = 12, .day = 31 };

    try testing.expect(date1.eql(date2));
}

test "Logger.Date.eql year boundary difference" {
    const date1 = Logger.Date{ .year = 2024, .month = 12, .day = 31 };
    const date2 = Logger.Date{ .year = 2025, .month = 1, .day = 1 };

    try testing.expect(!date1.eql(date2));
}

test "RotationPolicy.size creation" {
    const policy = RotationPolicy{ .size = 1024 * 1024 };

    switch (policy) {
        .size => |size| try testing.expectEqual(@as(usize, 1024 * 1024), size),
        else => try testing.expect(false),
    }
}

test "RotationPolicy.daily creation" {
    const policy = RotationPolicy{ .daily = {} };

    switch (policy) {
        .daily => {},
        else => try testing.expect(false),
    }
}

test "RotationPolicy.both creation" {
    const policy = RotationPolicy{ .both = 5 * 1024 * 1024 };

    switch (policy) {
        .both => |size| try testing.expectEqual(@as(usize, 5 * 1024 * 1024), size),
        else => try testing.expect(false),
    }
}
