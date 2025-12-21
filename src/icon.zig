const w32 = @import("win32").everything;

const constant = @import("constant.zig");
const win32 = @import("win32.zig");

pub const Icon = struct {
    lock: ?w32.HICON = null,
    unlock: ?w32.HICON = null,

    pub fn init(self: *Icon) void {
        const instance = win32.getModuleHandle();

        self.lock = loadIconWithFallback(instance, constant.Resource.LOCK_ICON, w32.IDI_SHIELD);
        self.unlock = loadIconWithFallback(instance, constant.Resource.UNLOCK_ICON, w32.IDI_APPLICATION);
    }

    pub fn deinit(self: *Icon) void {
        win32.destroyIcon(self.lock);
        win32.destroyIcon(self.unlock);
        self.lock = null;
        self.unlock = null;
    }

    pub fn current(self: *const Icon, locked: bool) ?w32.HICON {
        return if (locked) self.lock else self.unlock;
    }

    fn loadIconWithFallback(instance: w32.HINSTANCE, resourceId: usize, fallback: anytype) ?w32.HICON {
        const icon: ?w32.HICON = @ptrCast(w32.LoadImageW(
            instance,
            @ptrFromInt(resourceId),
            w32.IMAGE_ICON,
            0,
            0,
            w32.LR_DEFAULTCOLOR,
        ));

        return icon orelse w32.LoadIconW(null, fallback);
    }
};
