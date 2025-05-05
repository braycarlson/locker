#include "../include/window.h"

HINSTANCE hInstance;

LRESULT CALLBACK lpfnWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_USER + 1:
            if (LOWORD(lParam) == WM_LBUTTONUP || LOWORD(lParam) == WM_RBUTTONUP) {
                showContextMenu(locker->tray);
            }

            break;

        case WM_LBUTTONUP:
        case WM_RBUTTONUP:
            showContextMenu(locker->tray);
            break;

        case WM_DESTROY:
            PostMessageW(hwnd, WM_CLOSE, 0, 0);
            break;

        case WM_CLOSE:
            handleMenuCommand(locker->tray, wParam);
            PostQuitMessage(0);
            break;

        case WM_COMMAND:
            handleMenuCommand(locker->tray, wParam);
            break;

        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
    return 0;
}

HWND createWindow(LPCWSTR lpszClassName, HICON hIcon) {
    WNDCLASSW wc = {0};
    wc.lpfnWndProc = lpfnWndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = lpszClassName;
    wc.hIcon = hIcon;

    if (!RegisterClassW(&wc)) {
        MessageBoxW(NULL, L"Failed to register window class.", L"Error", MB_ICONERROR);
        return NULL;
    }

    HWND hwnd = CreateWindowW(
        lpszClassName,
        lpszClassName,
        0,
        CW_USEDEFAULT, CW_USEDEFAULT,
        0, 0,
        NULL, NULL,
        hInstance,
        NULL
    );

    if (!hwnd) {
        MessageBoxW(NULL, L"Failed to create main window.", L"Error", MB_ICONERROR);
    }

    return hwnd;
}

void setIcon(HWND hwnd, HICON icon) {
    SendMessageW(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)icon);
    SendMessageW(hwnd, WM_SETICON, ICON_BIG, (LPARAM)icon);
}
