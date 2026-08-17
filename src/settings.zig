const std = @import("std");

const arc = @import("arc");
const umbra = @import("umbra");

const Config = @import("config.zig").Config;

const assert = std.debug.assert;

const Logger = arc.Logger;

pub const SettingsManager = struct {
    configuration: *Config,
    logger: ?*Logger,
    watch_handle: ?umbra.watcher.Handle,

    pub fn init(configuration: *Config, logger: ?*Logger) SettingsManager {
        return SettingsManager{
            .configuration = configuration,
            .logger = logger,
            .watch_handle = null,
        };
    }

    pub fn deinit(manager: *SettingsManager) void {
        const handle = manager.watch_handle orelse return;

        umbra.watcher.unwatch(handle);

        manager.watch_handle = null;

        assert(manager.watch_handle == null);
    }

    pub fn open(manager: *SettingsManager) void {
        const path = manager.configuration.get_config_path() orelse return;

        manager.log("Opening settings file");

        umbra.shell.open(path) catch {
            manager.log("Unable to open the settings file");

            return;
        };
    }

    pub fn reload(manager: *SettingsManager) bool {
        const path = manager.configuration.get_config_path() orelse return false;
        const content = manager.read_content(path) orelse return false;

        manager.configuration.parse(content) catch {
            manager.log("Rejected an invalid configuration");

            return false;
        };

        return true;
    }

    pub fn watch(
        manager: *SettingsManager,
        callback: umbra.watcher.Callback,
        context: ?*anyopaque,
    ) void {
        assert(manager.watch_handle == null);

        const path = manager.configuration.get_config_path() orelse return;

        manager.watch_handle = umbra.watcher.watch(path, callback, context) catch {
            manager.log("Unable to watch the settings file");

            return;
        };
    }

    fn log(manager: *SettingsManager, message: []const u8) void {
        assert(message.len > 0);

        if (manager.logger) |logger| {
            logger.info(message, &.{}, @src());
        }
    }

    fn read_content(manager: *SettingsManager, path: []const u8) ?[:0]const u8 {
        const io = manager.configuration.io;

        const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return null;
        defer file.close(io);

        const buffer = manager.configuration.content_buffer[0..Config.content_length_max];
        const count = file.readPositionalAll(io, buffer, 0) catch return null;

        if (count == 0) {
            return null;
        }

        manager.configuration.content_buffer[count] = 0;

        return manager.configuration.content_buffer[0..count :0];
    }
};

const testing = std.testing;

test "a fresh settings manager owns no watch" {
    var configuration = Config.init(testing.io);
    defer configuration.deinit();

    var settings = SettingsManager.init(&configuration, null);
    defer settings.deinit();

    try testing.expect(settings.watch_handle == null);
}

test "reload without a config path reports failure" {
    var configuration = Config.init(testing.io);
    defer configuration.deinit();

    var settings = SettingsManager.init(&configuration, null);
    defer settings.deinit();

    try testing.expect(configuration.get_config_path() == null);
    try testing.expect(!settings.reload());
}
