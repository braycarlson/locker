const w32 = @import("win32").everything;

const constants = @import("constants.zig");

const SystemTray = @import("systemtray.zig").SystemTray;

pub const RehookTimer = struct {
    pub fn set(tray: *SystemTray) bool {
        if (!tray.isTimerActive) {
            const ok = w32.SetTimer(
                tray.window.handle,
                constants.Timer.REHOOK_ID,
                constants.Timer.REHOOK_INTERVAL_MS,
                null,
            ) != 0;

            tray.isTimerActive = ok;
        }

        return tray.isTimerActive;
    }

    pub fn kill(tray: *SystemTray) void {
        if (tray.isTimerActive) {
            _ = w32.KillTimer(tray.window.handle, constants.Timer.REHOOK_ID);
            tray.isTimerActive = false;
        }
    }
};
