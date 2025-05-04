const std = @import("std");
const testing = std.testing;

const w32 = @import("win32").everything;

pub const Hotkey = struct {
    pub const lock: []const u8 = &[_]u8{ 162, 164, 76 };
    pub const unlock: []const u8 = &[_]u8{ 85, 78, 76, 79, 67, 75 };
};

pub const MenuIdentifier = struct {
    pub const TOGGLE = 1001;
    pub const EXIT = 1002;
};

pub const ResourceIdentifier = struct {
    pub const LOCK_ICON = 101;
    pub const UNLOCK_ICON = 102;
};

pub const Timer = struct {
    pub const REHOOK_ID: usize = 1;
    pub const REHOOK_INTERVAL_MS: u32 = 10 * 60 * 1000;
};

pub const VirtualKey = enum(u32) {
    escape = 27,
    space = 32,
    context = 93,
};

pub const Keyboard = struct {
    pub const KEYS = [_]u32{
        @intFromEnum(VirtualKey.context),
        @intFromEnum(VirtualKey.escape),
        @intFromEnum(VirtualKey.space),
    };

    pub fn isBlockedKey(key: u32) bool {
        inline for (KEYS) |blockable| {
            if (key == blockable) return true;
        }

        return false;
    }

    pub const MESSAGES = [_]u32{
        w32.WM_KEYDOWN,
        w32.WM_SYSKEYDOWN,
    };

    pub fn isBlockedMessage(message: usize) bool {
        inline for (MESSAGES) |blockable| {
            if (@as(u32, @truncate(message)) == blockable) return true;
        }

        return false;
    }
};

pub const Mouse = struct {
    pub const MESSAGES = [_]u32{
        w32.WM_LBUTTONDOWN,
        w32.WM_MBUTTONDOWN,
        w32.WM_RBUTTONDOWN,
        w32.WM_XBUTTONDOWN,
        w32.WM_LBUTTONUP,
        w32.WM_MBUTTONUP,
        w32.WM_RBUTTONUP,
        w32.WM_XBUTTONUP,
        w32.WM_MOUSEWHEEL,
    };

    pub fn isBlockedMessage(message: usize) bool {
        inline for (MESSAGES) |blocked_msg| {
            if (@as(u32, @truncate(message)) == blocked_msg) return true;
        }
        return false;
    }
};

pub const WM_TRAYICON = w32.WM_APP + 1;
