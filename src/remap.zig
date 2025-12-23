const std = @import("std");

const toolkit = @import("toolkit");

const Config = @import("config.zig").Config;
const KeyCombination = @import("config.zig").KeyCombination;
const Logger = @import("logger.zig").Logger;

const modifier_count: u32 = 4;

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

    fn handleWindowsKey(self: *Remap, code: u32, is_down: bool) ?u32 {
        std.debug.assert(isWindowsKey(code));
        std.debug.assert(code > 0);

        if (is_down) {
            self.shortcut_invoked = false;
            return null;
        }

        std.debug.assert(!is_down);

        if (!self.shortcut_invoked) {
            return null;
        }

        std.debug.assert(self.shortcut_invoked);

        self.shortcut_invoked = false;
        toolkit.input.Sender.suppressKey(code);

        return 0;
    }

    pub fn process(self: *Remap, code: u32, is_down: bool, extra_info: usize) ?u32 {
        std.debug.assert(code > 0);
        std.debug.assert(self.config.remap_count <= Config.remap_max);
        std.debug.assert(self.config.disabled_count <= Config.disabled_max);

        if (extra_info == toolkit.input.injected_flag) {
            return null;
        }

        if (isWindowsKey(code)) {
            return self.handleWindowsKey(code, is_down);
        }

        if (!is_down) {
            return null;
        }

        if (toolkit.input.isModifierKey(code)) {
            return null;
        }

        const modifier = toolkit.input.ModifierSet.poll();

        if (!modifier.win) {
            return null;
        }

        std.debug.assert(modifier.win);

        if (self.config.isDisabled(code, modifier)) {
            self.shortcut_invoked = true;

            if (self.logger.*) |*l| {
                l.log("Blocked a disabled shortcut", .{});
            }

            return 0;
        }

        if (self.config.findRemapEntry(code, modifier)) |entry| {
            std.debug.assert(entry.from.key > 0);
            std.debug.assert(entry.to.key > 0);

            self.shortcut_invoked = true;

            if (self.logger.*) |*l| {
                l.log("Remapped a shortcut", .{});
            }

            sendRemappedShortcut(entry.from, entry.to);

            return 0;
        }

        return null;
    }
};

fn isModifierInSet(array: [4]?toolkit.input.Modifier, target: toolkit.input.Modifier) bool {
    var index: u32 = 0;

    while (index < modifier_count) : (index += 1) {
        std.debug.assert(index < modifier_count);

        if (array[index]) |mod| {
            if (mod == target) {
                return true;
            }
        }
    }

    std.debug.assert(index == modifier_count);

    return false;
}

fn isWindowsKey(code: u32) bool {
    std.debug.assert(code > 0);

    return code == toolkit.input.VirtualKey.lwin or
        code == toolkit.input.VirtualKey.rwin;
}

fn sendRemappedShortcut(from: KeyCombination, to: KeyCombination) void {
    std.debug.assert(from.key > 0);
    std.debug.assert(to.key > 0);

    const from_array = from.modifier.toArray();
    const to_array = to.modifier.toArray();

    toolkit.input.Sender.dummy();

    var index: u32 = 0;

    while (index < modifier_count) : (index += 1) {
        std.debug.assert(index < modifier_count);

        if (from_array[index]) |mod| {
            if (!isModifierInSet(to_array, mod)) {
                toolkit.input.Sender.keyUp(mod.toVirtualKey());
            }
        }
    }

    std.debug.assert(index == modifier_count);

    index = 0;

    while (index < modifier_count) : (index += 1) {
        std.debug.assert(index < modifier_count);

        if (to_array[index]) |mod| {
            if (!isModifierInSet(from_array, mod)) {
                toolkit.input.Sender.keyDown(mod.toVirtualKey());
            }
        }
    }

    std.debug.assert(index == modifier_count);

    toolkit.input.Sender.key(to.key);

    var release: u32 = modifier_count;
    var iteration: u32 = 0;

    while (release > 0) : (release -= 1) {
        std.debug.assert(iteration < modifier_count);

        const idx = release - 1;

        std.debug.assert(idx < modifier_count);

        if (to_array[idx]) |mod| {
            if (!isModifierInSet(from_array, mod)) {
                toolkit.input.Sender.keyUp(mod.toVirtualKey());
            }
        }

        iteration += 1;
    }

    std.debug.assert(iteration == modifier_count);
}
