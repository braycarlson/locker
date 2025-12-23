const toolkit = @import("toolkit");

pub const Menu = struct {
    pub const exit: u32 = 1002;
    pub const settings: u32 = 1005;
    pub const toggle: u32 = 1001;
    pub const toggle_keyboard: u32 = 1003;
    pub const toggle_mouse: u32 = 1004;
};

pub const Resource = struct {
    pub const lock_icon: u32 = 101;
    pub const unlock_icon: u32 = 102;
};

pub const Timer = struct {
    pub const rehook_id: usize = 1;
    pub const rehook_interval_ms: u32 = 10 * 60 * 1000;
};

pub const wm_config_reload: u32 = @import("win32").everything.WM_APP + 2;
