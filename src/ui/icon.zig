const std = @import("std");
const w32 = @import("win32").everything;

const constant = @import("../constant.zig");
const win32 = @import("../os/win32.zig");

pub const Icon = struct {
    lock: ?w32.HICON = null,
    unlock: ?w32.HICON = null,

    pub fn init(self: *Icon) void {
        std.debug.assert(self.lock == null);
        std.debug.assert(self.unlock == null);

        const instance = win32.getModuleHandle();

        self.lock = loadIcon(instance, constant.Resource.lock_icon, w32.IDI_SHIELD);
        self.unlock = loadIcon(instance, constant.Resource.unlock_icon, w32.IDI_APPLICATION);

        if (self.lock == null) {
            std.debug.assert(self.lock == null);
        }

        if (self.unlock == null) {
            std.debug.assert(self.unlock == null);
        }
    }

    pub fn deinit(self: *Icon) void {
        if (self.lock) |_| {
            win32.destroyIcon(self.lock);
        }

        if (self.unlock) |_| {
            win32.destroyIcon(self.unlock);
        }

        self.lock = null;
        self.unlock = null;

        std.debug.assert(self.lock == null);
        std.debug.assert(self.unlock == null);
    }

    fn loadIcon(instance: w32.HINSTANCE, resource_id: usize, fallback: anytype) ?w32.HICON {
        std.debug.assert(resource_id > 0);

        const icon: ?w32.HICON = @ptrCast(w32.LoadImageW(
            instance,
            @ptrFromInt(resource_id),
            w32.IMAGE_ICON,
            0,
            0,
            w32.LR_DEFAULTCOLOR,
        ));

        if (icon != null) {
            std.debug.assert(icon != null);

            return icon;
        }

        std.debug.assert(icon == null);

        return w32.LoadIconW(null, fallback);
    }

    pub fn current(self: *const Icon, is_locked: bool) ?w32.HICON {
        if (is_locked) {
            return self.lock;
        }

        return self.unlock;
    }
};
