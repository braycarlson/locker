#include "../include/icon.h"

HICON loadIconFromResources(HINSTANCE hInstance, bool isLocked) {
    int iconID = isLocked ? IDR_LOCK_ICON : IDR_UNLOCK_ICON;
    HICON hIcon = (HICON)LoadImageW(hInstance, MAKEINTRESOURCE(iconID), IMAGE_ICON, 0, 0, LR_DEFAULTCOLOR);

    if (!hIcon) {
        MessageBoxW(NULL, L"Failed to load icon.", L"Error", MB_ICONERROR);
    }

    return hIcon;
}
