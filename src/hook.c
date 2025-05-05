#include "../include/hook.h"
#include "../include/locker.h"

HHOOK hKeyboardHook = NULL;
HHOOK hMouseHook = NULL;

HOOKPROC KeyboardProcPtr = NULL;
HOOKPROC MouseProcPtr = NULL;

LRESULT CALLBACK KeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode >= 0 && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
        KBDLLHOOKSTRUCT* kbdstruct = (KBDLLHOOKSTRUCT*)lParam;
        unsigned char key = (unsigned char)kbdstruct->vkCode;

        push(locker->queue, key);

        if (locker->isLocked) {
            if (isMatch(locker->queue, locker->unlockHotkey, 6)) {
                toggleLock(locker, false);
            }

            return 1;
        } else {
            if (isMatch(locker->queue, locker->lockHotkey, 3)) {
                toggleLock(locker, true);
            }
        }
    }

    return CallNextHookEx(NULL, nCode, wParam, lParam);
}

LRESULT CALLBACK MouseProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode >= 0 && locker->isLocked) {
        return 1;
    }

    return CallNextHookEx(NULL, nCode, wParam, lParam);
}

void setKeyboardProc(HOOKPROC KeyboardProc) {
    KeyboardProcPtr = KeyboardProc;
}

void setMouseProc(HOOKPROC MouseProc) {
    (void)MouseProc;
    // MouseProcPtr = MouseProc;
}

void setKeyboardHook() {
    if (KeyboardProcPtr) {
        hKeyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardProcPtr, NULL, 0);
    }
}

void setMouseHook() {
    if (MouseProcPtr) {
        hMouseHook = SetWindowsHookEx(WH_MOUSE_LL, MouseProcPtr, NULL, 0);
    }
}

void removeHook() {
    if (hKeyboardHook) {
        UnhookWindowsHookEx(hKeyboardHook);
        hKeyboardHook = NULL;
    }

    if (hMouseHook) {
        UnhookWindowsHookEx(hMouseHook);
        hMouseHook = NULL;
    }
}
