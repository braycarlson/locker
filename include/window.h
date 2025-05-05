#ifndef WINDOWS_H
#define WINDOWS_H

#include "hook.h"
#include "windows.h"

#include "../include/locker.h"
#include "../include/tray.h"

extern HINSTANCE hInstance;

HWND createWindow(LPCWSTR className, HICON icon);
LRESULT CALLBACK lpfnWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
void setIcon(HWND hwnd, HICON icon);

#endif // WINDOWS_H
