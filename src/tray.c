#include "../include/tray.h"

void initializeTray(Tray* tray, HINSTANCE hInstance, HWND hwnd) {
    if (!tray) {
        MessageBoxW(NULL, L"Failed to initialize tray.", L"Error", MB_ICONERROR);
        return;
    }

    tray->hInstance = hInstance;
    tray->hwnd = hwnd;
    tray->isTrayIconAdded = false;
    memset(&tray->nid, 0, sizeof(NOTIFYICONDATAW));
    tray->nid.cbSize = sizeof(NOTIFYICONDATAW);
    tray->nid.hWnd = hwnd;
    tray->nid.uID = 1;
    tray->nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    tray->nid.uCallbackMessage = WM_USER + 1;

    if (!Shell_NotifyIconW(NIM_ADD, &tray->nid)) {
        return;
    }

    tray->isTrayIconAdded = true;
}

void handleMenuCommand(Tray* tray, WPARAM wParam) {
    if (LOWORD(wParam) == 1) {
        Shell_NotifyIconW(NIM_DELETE, &tray->nid);
        PostQuitMessage(0);
    }
}

void showContextMenu(Tray* tray) {
    HMENU hMenu = CreatePopupMenu();

    if (!hMenu) {
        return;
    }

    AppendMenuW(hMenu, MF_STRING, 1, L"Exit");

    POINT pt;

    if (!GetCursorPos(&pt)) {
        DestroyMenu(hMenu);
        MessageBoxW(NULL, L"Failed to get cursor position", L"Error", MB_ICONERROR);
        return;
    }

    SetForegroundWindow(tray->hwnd);
    TrackPopupMenu(hMenu, TPM_BOTTOMALIGN | TPM_LEFTALIGN, pt.x, pt.y, 0, tray->hwnd, NULL);

    DestroyMenu(hMenu);
}

void updateIcon(Tray* tray, bool isLocked) {
    HICON hIcon = loadIconFromResources(tray->hInstance, isLocked);

    if (!hIcon) {
        MessageBoxW(NULL, L"Failed to load icon", L"Error", MB_ICONERROR);
        return;
    }

    tray->nid.uFlags = NIF_ICON | NIF_TIP;
    tray->nid.hIcon = hIcon;

    wcscpy(tray->nid.szTip, isLocked ? L"Locked" : L"Unlocked");

    if (!tray->isTrayIconAdded) {
        if (Shell_NotifyIconW(NIM_ADD, &tray->nid)) {
            tray->isTrayIconAdded = true;
        } else {
            DestroyIcon(hIcon);
            MessageBoxW(NULL, L"Failed to add tray icon", L"Error", MB_ICONERROR);
            return;
        }
    } else {
        if (!Shell_NotifyIconW(NIM_MODIFY, &tray->nid)) {
            MessageBoxW(NULL, L"Failed to update tray icon", L"Error", MB_ICONERROR);
        }
    }

    DestroyIcon(hIcon);
}

Tray* createTray(HINSTANCE hInstance, HWND hwnd) {
    Tray* tray = (Tray*)malloc(sizeof(Tray));

    if (!tray) {
        MessageBoxW(NULL, L"Failed to allocate memory for tray", L"Error", MB_ICONERROR);
        return NULL;
    }

    initializeTray(tray, hInstance, hwnd);
    return tray;
}

void cleanupTray(Tray* tray) {
    if (tray) {
        if (tray->isTrayIconAdded) {
            Shell_NotifyIconW(NIM_DELETE, &tray->nid);
        }

        free(tray);
    }
}
