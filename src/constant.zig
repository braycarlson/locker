const w32 = @import("win32").everything;

pub const File = struct {
    pub const list_directory: u32 = 0x0001;
    pub const flag_backup_semantics: u32 = 0x02000000;
};

pub const Menu = struct {
    pub const toggle: u32 = 1001;
    pub const exit: u32 = 1002;
    pub const toggle_keyboard: u32 = 1003;
    pub const toggle_mouse: u32 = 1004;
    pub const settings: u32 = 1005;
};

pub const Resource = struct {
    pub const lock_icon: u32 = 101;
    pub const unlock_icon: u32 = 102;
};

pub const Timer = struct {
    pub const rehook_id: usize = 1;
    pub const rehook_interval_ms: u32 = 10 * 60 * 1000;
};

pub const wm_trayicon: u32 = w32.WM_APP + 1;
pub const wm_config_reload: u32 = w32.WM_APP + 2;
