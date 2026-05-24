const std = @import("std");
const path_util = @import("path.zig");

pub const backup_count_max: u32 = 5;
pub const buffer_size: u32 = 4096;
pub const path_length_max: u32 = 512;

pub const RotationPolicy = union(enum) {
    both: usize,
    daily: void,
    size: usize,
};

pub const Date = struct {
    day: u5,
    month: u4,
    year: u16,

    pub fn current() Date {
        const timestamp = std.time.timestamp();
        std.debug.assert(timestamp >= 0);

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

    pub fn eql(self: *const Date, other: *const Date) bool {
        return self.year == other.year and self.month == other.month and self.day == other.day;
    }
};

pub const LoggerError = error{
    InvalidPath,
    DirectoryCreationFailed,
    FileOpenFailed,
    StatFailed,
    SeekFailed,
    RotationFailed,
    FormatFailed,
    WriteFailed,
};

pub const Logger = struct {
    current_size: u32 = 0,
    file: ?std.fs.File = null,
    last_date: ?Date = null,
    mutex: std.Thread.Mutex = .{},
    path: [path_length_max]u8 = [_]u8{0} ** path_length_max,
    path_length: u32 = 0,
    policy: RotationPolicy,
    write_error: u32 = 0,

    pub fn init(policy: RotationPolicy) LoggerError!Logger {
        var result = Logger{ .policy = policy };

        result.load_path() catch {
            return LoggerError.InvalidPath;
        };

        std.debug.assert(result.path_length > 0);
        std.debug.assert(result.path_length <= path_length_max);

        result.open_file() catch |err| {
            return err;
        };

        std.debug.assert(result.file != null);

        return result;
    }

    pub fn deinit(self: *Logger) void {
        if (self.file) |file| {
            file.close();
            self.file = null;
        }
    }

    pub fn log(self: *Logger, comptime format: []const u8, argument: anytype) void {
        std.debug.assert(format.len > 0);

        self.mutex.lock();
        defer self.mutex.unlock();

        self.ensure_file_ready() catch {
            return;
        };

        var buffer: [buffer_size]u8 = undefined;

        const content = self.format_message(&buffer, format, argument) catch {
            return;
        };

        self.write_to_file(content);
    }

    fn ensure_file_ready(self: *Logger) LoggerError!void {
        if (self.should_rotate()) {
            self.rotate() catch {
                self.write_error += 1;
                return LoggerError.RotationFailed;
            };
        }

        if (self.file == null) {
            self.write_error += 1;
            return LoggerError.FileOpenFailed;
        }
    }

    fn format_message(
        self: *Logger,
        buffer: *[buffer_size]u8,
        comptime format: []const u8,
        argument: anytype,
    ) LoggerError![]const u8 {
        var fixed_buffer_stream = std.io.fixedBufferStream(buffer);
        const writer = fixed_buffer_stream.writer();

        self.write_timestamp(writer) catch {
            self.write_error += 1;
            return LoggerError.FormatFailed;
        };

        writer.print(format ++ "\n", argument) catch {
            self.write_error += 1;
            return LoggerError.FormatFailed;
        };

        return fixed_buffer_stream.getWritten();
    }

    fn get_path_slice(self: *const Logger) []const u8 {
        std.debug.assert(self.path_length > 0);
        std.debug.assert(self.path_length <= path_length_max);

        return self.path[0..self.path_length];
    }

    fn has_date_changed(self: *const Logger) bool {
        const today = Date.current();

        if (self.last_date) |last| {
            return !today.eql(&last);
        }

        return false;
    }

    fn load_path(self: *Logger) LoggerError!void {
        var buffer: [path_length_max]u8 = undefined;

        const base = path_util.get_appdata_path(&buffer, "locker") catch {
            return LoggerError.InvalidPath;
        };

        const full_path = path_util.join_path(&self.path, base, "locker.log") orelse {
            return LoggerError.InvalidPath;
        };

        self.path_length = @intCast(full_path.len);
    }

    fn open_file(self: *Logger) LoggerError!void {
        std.debug.assert(self.path_length > 0);

        const path = self.get_path_slice();
        const directory = std.fs.path.dirname(path) orelse {
            return LoggerError.InvalidPath;
        };

        std.fs.makeDirAbsolute(directory) catch |err| {
            if (err != error.PathAlreadyExists) {
                return LoggerError.DirectoryCreationFailed;
            }
        };

        self.file = std.fs.createFileAbsolute(path, .{ .read = true, .truncate = false }) catch {
            return LoggerError.FileOpenFailed;
        };

        const stat = self.file.?.stat() catch {
            return LoggerError.StatFailed;
        };

        self.current_size = @intCast(stat.size);

        self.file.?.seekFromEnd(0) catch {
            return LoggerError.SeekFailed;
        };

        self.last_date = Date.current();
    }

    fn rotate(self: *Logger) LoggerError!void {
        std.debug.assert(self.path_length > 0);

        if (self.file) |file| {
            file.close();
            self.file = null;
        }

        self.rotate_file();

        self.open_file() catch |err| {
            return err;
        };

        self.current_size = 0;
        self.last_date = Date.current();
    }

    fn rotate_file(self: *Logger) void {
        const path = self.get_path_slice();

        var old_path_buffer: [path_length_max + 8]u8 = undefined;
        var new_path_buffer: [path_length_max + 8]u8 = undefined;

        var backup_index: u32 = backup_count_max;

        while (backup_index > 0) : (backup_index -= 1) {
            const old_path = if (backup_index == 1)
                path
            else
                std.fmt.bufPrint(&old_path_buffer, "{s}.{d}", .{ path, backup_index - 1 }) catch continue;

            const new_path = std.fmt.bufPrint(&new_path_buffer, "{s}.{d}", .{ path, backup_index }) catch continue;

            if (backup_index == backup_count_max) {
                std.fs.deleteFileAbsolute(new_path) catch {};
            }

            std.fs.renameAbsolute(old_path, new_path) catch {};
        }
    }

    fn should_rotate(self: *const Logger) bool {
        return switch (self.policy) {
            .size => |max_size| self.current_size >= max_size,
            .daily => self.has_date_changed(),
            .both => |max_size| (self.current_size >= max_size) or self.has_date_changed(),
        };
    }

    fn write_timestamp(self: *const Logger, writer: anytype) !void {
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

    fn write_to_file(self: *Logger, content: []const u8) void {
        std.debug.assert(content.len > 0);

        const file = self.file orelse return;
        const length: u32 = @intCast(content.len);

        const count = file.write(content) catch {
            self.write_error += 1;
            return;
        };

        if (count != content.len) {
            self.write_error += 1;
        }

        file.sync() catch {
            self.write_error += 1;
        };

        self.current_size += length;
    }
};
