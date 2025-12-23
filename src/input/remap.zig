const std = @import("std");

const Config = @import("../config.zig").Config;
const input = @import("sender.zig");
const keycode = @import("keycode.zig");
const Logger = @import("../logger.zig").Logger;

pub const Remap = struct {
    config: *Config,
    logger: *?Logger,
    shortcut_invoked: bool = false,

    pub fn init(cfg: *Config, logger: *?Logger) Remap {
        std.debug.assert(cfg.remap_count <= Config.remap_max);
        std.debug.assert(cfg.disabled_count <= Config.disabled_max);

        return .{
            .config = cfg,
            .logger = logger,
        };
    }

    fn handleWindowsKey(self: *Remap, virtual_key_code: u32, is_key_down: bool) ?u32 {
        std.debug.assert(isWindowsKey(virtual_key_code));
        std.debug.assert(virtual_key_code > 0);

        if (is_key_down) {
            self.shortcut_invoked = false;

            std.debug.assert(!self.shortcut_invoked);

            return null;
        }

        std.debug.assert(!is_key_down);

        if (!self.shortcut_invoked) {
            return null;
        }

        std.debug.assert(self.shortcut_invoked);

        self.shortcut_invoked = false;
        input.suppressWindowsKey(virtual_key_code);

        std.debug.assert(!self.shortcut_invoked);

        return 0;
    }

    fn isWindowsKey(virtual_key_code: u32) bool {
        std.debug.assert(virtual_key_code > 0);

        if (virtual_key_code == keycode.VirtualKey.lwin) {
            return true;
        }

        if (virtual_key_code == keycode.VirtualKey.rwin) {
            return true;
        }

        return false;
    }

    pub fn process(self: *Remap, virtual_key_code: u32, is_key_down: bool, extra_info: usize) ?u32 {
        std.debug.assert(virtual_key_code > 0);
        std.debug.assert(self.config.remap_count <= Config.remap_max);
        std.debug.assert(self.config.disabled_count <= Config.disabled_max);

        if (extra_info == input.shortcut_flag) {
            return null;
        }

        if (isWindowsKey(virtual_key_code)) {
            return self.handleWindowsKey(virtual_key_code, is_key_down);
        }

        if (!is_key_down) {
            return null;
        }

        if (keycode.isModifierKey(virtual_key_code)) {
            return null;
        }

        const modifier = input.getCurrentModifier();

        if (!modifier.win) {
            return null;
        }

        std.debug.assert(modifier.win);

        if (self.config.isDisabled(virtual_key_code, modifier)) {
            self.shortcut_invoked = true;

            std.debug.assert(self.shortcut_invoked);

            if (self.logger.*) |*l| {
                l.log("Blocked a disabled shortcut", .{});
            }

            return 0;
        }

        if (self.config.findRemapEntry(virtual_key_code, modifier)) |entry| {
            std.debug.assert(entry.from.key > 0);
            std.debug.assert(entry.to.key > 0);

            self.shortcut_invoked = true;

            std.debug.assert(self.shortcut_invoked);

            if (self.logger.*) |*l| {
                l.log("Remapped a shortcut", .{});
            }

            input.sendRemappedShortcut(entry.from, entry.to);

            return 0;
        }

        return null;
    }
};
