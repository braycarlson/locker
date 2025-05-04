const std = @import("std");
const w32 = @import("win32").everything;

const constants = @import("constants.zig");
const hook = @import("hook.zig");

const LockerError = @import("error.zig").LockerError;

pub const Icon = struct {
    lock: ?w32.HICON = null,
    unlock: ?w32.HICON = null,

    pub fn init(self: *Icon) !void {
        const hmod = hook.getModuleHandle();

        self.lock = @ptrCast(w32.LoadImageW(hmod, @ptrFromInt(@as(usize, constants.ResourceIdentifier.LOCK_ICON)), w32.IMAGE_ICON, 0, 0, w32.LR_DEFAULTCOLOR));
        if (self.lock == null) self.lock = w32.LoadIconW(null, w32.IDI_SHIELD);

        self.unlock = @ptrCast(w32.LoadImageW(hmod, @ptrFromInt(@as(usize, constants.ResourceIdentifier.UNLOCK_ICON)), w32.IMAGE_ICON, 0, 0, w32.LR_DEFAULTCOLOR));
        if (self.unlock == null) self.unlock = w32.LoadIconW(null, w32.IDI_APPLICATION);

        if (self.lock == null or self.unlock == null) return LockerError.IconLoadFailed;
    }

    pub fn current(self: *Icon, locked: bool) w32.HICON {
        return if (locked) self.lock.? else self.unlock.?;
    }

    pub fn deinit(self: *Icon) void {
        if (self.lock) |h| {
            _ = w32.DestroyIcon(h);
            self.lock = null;
        }

        if (self.unlock) |h| {
            _ = w32.DestroyIcon(h);
            self.unlock = null;
        }
    }
};
