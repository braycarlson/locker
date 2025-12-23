const std = @import("std");

pub const RotationPolicy = union(enum) {
    both: usize,
    daily: void,
    size: usize,
};

pub const Logger = struct {
    const backup_max: u32 = 5;
    const buffer_size: u32 = 4096;
    const path_max: u32 = 512;

    const Date = struct {
        day: u5,
        month: u4,
        year: u16,

        fn eql(self: Date, other: Date) bool {
            return self.year == other.year and
                self.month == other.month and
                self.day == other.day;
        }
    };

    current_size: u32 = 0,
    file: ?std.fs.File = null,
    last_date: ?Date = null,
    mutex: std.Thread.Mutex = .{},
    path: [path_max]u8 = [_]u8{0} ** path_max,
    path_len: u32 = 0,
    policy: RotationPolicy,
    write_error: u32 = 0,

    pub fn init(path: []const u8, policy: RotationPolicy) !Logger {
        const length: u32 = @intCast(path.len);

        if (length == 0 or length > path_max) {
            return error.InvalidPath;
        }

        var self = Logger{ .policy = policy };

        @memcpy(self.path[0..length], path);
        self.path_len = length;

        try self.openFile();

        return self;
    }

    pub fn deinit(self: *Logger) void {
        if (self.file) |file| {
            file.close();
            self.file = null;
        }
    }

    fn ensureFileReady(self: *Logger) bool {
        if (self.shouldRotate()) {
            self.rotate() catch {
                self.write_error += 1;
                return false;
            };
        }

        if (self.file == null) {
            self.write_error += 1;
            return false;
        }

        return true;
    }

    fn formatMessage(self: *Logger, buffer: *[buffer_size]u8, comptime fmt: []const u8, args: anytype) ?[]const u8 {
        var fbs = std.io.fixedBufferStream(buffer);
        const writer = fbs.writer();

        self.writeTimestamp(writer) catch {
            self.write_error += 1;
            return null;
        };

        writer.print(fmt ++ "\n", args) catch {
            self.write_error += 1;
            return null;
        };

        return fbs.getWritten();
    }

    fn getCurrentDate(self: *Logger) Date {
        _ = self;

        const timestamp = std.time.timestamp();
        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = datetime.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return Date{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
        };
    }

    fn getPathSlice(self: *Logger) []const u8 {
        return self.path[0..self.path_len];
    }

    fn hasDateChanged(self: *Logger) bool {
        const current = self.getCurrentDate();
        const last = self.last_date orelse return false;

        return !current.eql(last);
    }

    fn openFile(self: *Logger) !void {
        const path = self.getPathSlice();
        const directory = std.fs.path.dirname(path) orelse return error.InvalidPath;

        std.fs.makeDirAbsolute(directory) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };

        self.file = try std.fs.createFileAbsolute(path, .{ .read = true, .truncate = false });

        const stat = try self.file.?.stat();
        self.current_size = @intCast(stat.size);

        try self.file.?.seekFromEnd(0);

        self.last_date = self.getCurrentDate();
    }

    fn rotate(self: *Logger) !void {
        if (self.file) |file| {
            file.close();
            self.file = null;
        }

        try self.rotateFile();
        try self.openFile();

        self.current_size = 0;
        self.last_date = self.getCurrentDate();
    }

    fn rotateFile(self: *Logger) !void {
        const path = self.getPathSlice();

        var old_path_buf: [path_max + 8]u8 = undefined;
        var new_path_buf: [path_max + 8]u8 = undefined;

        var i: u32 = backup_max;

        while (i > 0) : (i -= 1) {
            const old_path = if (i == 1)
                path
            else
                std.fmt.bufPrint(&old_path_buf, "{s}.{d}", .{ path, i - 1 }) catch continue;

            const new_path = std.fmt.bufPrint(&new_path_buf, "{s}.{d}", .{ path, i }) catch continue;

            if (i == backup_max) {
                std.fs.deleteFileAbsolute(new_path) catch {};
            }

            std.fs.renameAbsolute(old_path, new_path) catch {};
        }
    }

    fn shouldRotate(self: *Logger) bool {
        switch (self.policy) {
            .size => |max_size| return self.current_size >= max_size,
            .daily => return self.hasDateChanged(),
            .both => |max_size| return self.current_size >= max_size or self.hasDateChanged(),
        }
    }

    fn writeTimestamp(self: *Logger, writer: anytype) !void {
        _ = self;

        const timestamp = std.time.timestamp();
        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = datetime.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = datetime.getDaySeconds();

        try writer.print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        });
    }

    fn writeToFile(self: *Logger, written: []const u8) void {
        const file = self.file orelse return;
        const length: u32 = @intCast(written.len);

        const count = file.write(written) catch {
            self.write_error += 1;
            return;
        };

        if (count != written.len) {
            self.write_error += 1;
        }

        file.sync() catch {
            self.write_error += 1;
        };

        self.current_size += length;
    }

    pub fn log(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.ensureFileReady()) {
            return;
        }

        var buffer: [buffer_size]u8 = undefined;

        const written = self.formatMessage(&buffer, fmt, args) orelse return;

        self.writeToFile(written);
    }
};
