#include <stdio.h>
#include <windows.h>

#include "../include/hook.h"
#include "../include/locker.h"
#include "../include/resource.h"
#include "../include/tray.h"
#include "../include/window.h"

void cleanup() {
    cleanupLocker(locker);
}

int main() {
    atexit(cleanup);

    hInstance = GetModuleHandleW(NULL);

    if (!hInstance) {
        MessageBoxW(NULL, L"Failed to get module handle.", L"Error", MB_ICONERROR);
        return 1;
    }

    HICON hMainIcon = LoadIconW(hInstance, MAKEINTRESOURCE(MAINICON));

    if (!hMainIcon) {
        MessageBoxW(NULL, L"Failed to load icon.", L"Error", MB_ICONERROR);
        return 1;
    }

    LPCWSTR lpszClassName = L"Peripheral Locker";
    HWND hwnd = createWindow(lpszClassName, hMainIcon);

    if (!hwnd) {
        MessageBoxW(NULL, L"Failed to create the window.", L"Error", MB_ICONERROR);
        return 1;
    }

    setIcon(hwnd, hMainIcon);

    createLocker(hwnd);

    if (!locker) {
        MessageBoxW(NULL, L"Failed to initialize locker.", L"Error", MB_ICONERROR);
        DestroyWindow(hwnd);
        return 1;
    }

    if (!locker->tray) {
        MessageBoxW(NULL, L"Failed to initialize tray icon.", L"Error", MB_ICONERROR);
        DestroyWindow(hwnd);
        return 1;
    }

    updateIcon(locker->tray, locker->isLocked);

    MSG msg;

    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    return 0;
}
