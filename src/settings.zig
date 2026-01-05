const std = @import("std");

const w32 = @import("win32").everything;
const wisp = @import("wisp");

const Config = @import("config.zig").Config;
const Logger = @import("logger.zig").Logger;

pub const SettingsManager = struct {
    configuration: *Config,
    logger: ?*Logger,
    watcher: wisp.Watcher,

    pub fn init(configuration: *Config, logger: ?*Logger) SettingsManager {
        return SettingsManager{
            .configuration = configuration,
            .logger = logger,
            .watcher = wisp.Watcher.init(),
        };
    }

    pub fn deinit(self: *SettingsManager) void {
        self.watcher.deinit();
    }

    pub fn open(self: *SettingsManager) void {
        const path = self.configuration.get_config_path() orelse return;

        self.log("Opening settings file");
        open_path(path);
    }

    pub fn reload(self: *SettingsManager) bool {
        const path = self.configuration.config_path[0..self.configuration.config_path_length];

        const content = self.read_content(path) orelse return false;

        self.configuration.reset();
        self.configuration.parse(content) catch return false;

        return true;
    }

    pub fn watch(self: *SettingsManager, callback: *const fn () void) void {
        const path = self.configuration.get_config_path() orelse return;
        self.watcher.watch(path, callback) catch {};
    }

    fn log(self: *SettingsManager, message: []const u8) void {
        if (self.logger) |logger| {
            logger.log("{s}", .{message});
        }
    }

    fn read_content(self: *SettingsManager, path: []const u8) ?[:0]const u8 {
        const file = std.fs.openFileAbsolute(path, .{}) catch return null;
        defer file.close();

        const count = file.readAll(self.configuration.content_buffer[0..Config.content_length_max]) catch return null;

        if (count == 0) {
            return null;
        }

        self.configuration.content_buffer[count] = 0;

        return self.configuration.content_buffer[0..count :0];
    }
};

fn open_path(path: []const u8) void {
    if (path.len == 0 or path.len > Config.path_length_max) {
        return;
    }

    var buffer: [Config.path_length_max]u16 = undefined;

    const length = std.unicode.utf8ToUtf16Le(&buffer, path) catch return;

    if (length == 0 or length >= Config.path_length_max) {
        return;
    }

    buffer[length] = 0;

    _ = w32.ShellExecuteW(
        null,
        std.unicode.utf8ToUtf16LeStringLiteral("open"),
        @ptrCast(&buffer),
        null,
        null,
        1,
    );
}
