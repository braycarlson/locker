#ifndef TRAY_H
#define TRAY_H

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

#include "../include/icon.h"
#include "../include/resource.h"

typedef struct Tray {
    HINSTANCE hInstance;
    HWND hwnd;
    NOTIFYICONDATAW nid;
    bool isTrayIconAdded;
} Tray;

void initializeTray(Tray* tray, HINSTANCE hInstance, HWND hwnd);
void handleMenuCommand(Tray* tray, WPARAM wParam);
void showContextMenu(Tray* tray);
void updateIcon(Tray* tray, bool isLocked);

Tray* createTray(HINSTANCE hInstance, HWND hwnd);
void cleanupTray(Tray* tray);

#endif // TRAY_H
