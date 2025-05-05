#include "../include/hook.h"
#include "../include/locker.h"

Locker* locker;

void cleanupLocker(Locker* locker) {
    if (locker) {
        removeHook();

        free(locker->lockHotkey);
        free(locker->unlockHotkey);

        cleanupBuffer(locker->queue);
        cleanupTray(locker->tray);

        free(locker);
    }
}

void createLocker(HWND hwnd) {
    locker = (Locker*)malloc(sizeof(Locker));
    locker->queue = createBuffer(7);
    locker->tray = createTray(GetModuleHandleW(NULL), hwnd);
    locker->lockHotkey = (unsigned char*)malloc(3 * sizeof(unsigned char));
    locker->unlockHotkey = (unsigned char*)malloc(6 * sizeof(unsigned char));

    unsigned char lockHotkey[] = {162, 164, 76};
    unsigned char unlockHotkey[] = {85, 78, 76, 79, 67, 75};

    memcpy(locker->lockHotkey, lockHotkey, 3 * sizeof(unsigned char));
    memcpy(locker->unlockHotkey, unlockHotkey, 6 * sizeof(unsigned char));

    locker->isLocked = false;

    setKeyboardProc(KeyboardProc);
    setMouseProc(MouseProc);
    setKeyboardHook();
    setMouseHook();
}

void toggleLock(Locker* locker, bool lock) {
    locker->isLocked = lock;
    updateIcon(locker->tray, locker->isLocked);
}
