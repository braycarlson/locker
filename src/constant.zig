pub const Icon = struct {
    pub const dimension: u32 = 32;
};

pub const Menu = struct {
    pub const toggle: u32 = 1001;
    pub const exit: u32 = 1002;
    pub const toggle_keyboard: u32 = 1003;
    pub const toggle_mouse: u32 = 1004;
    pub const setting: u32 = 1005;
};

pub const Message = struct {
    pub const config_reload: u32 = 1;
    pub const lock: u32 = 2;
    pub const unlock: u32 = 3;
    pub const rescue: u32 = 4;
};

pub const Timer = struct {
    pub const rehook_id: u32 = 1;
    pub const rehook_interval_ms: u32 = 10 * 60 * 1000;
};
