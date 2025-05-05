#ifndef HOOK_H
#define HOOK_H

#include <stdio.h>
#include <windows.h>

#include "locker.h"

extern Locker* locker;

LRESULT CALLBACK KeyboardProc(int nCode, WPARAM wParam, LPARAM lParam);
LRESULT CALLBACK MouseProc(int nCode, WPARAM wParam, LPARAM lParam);

void removeHook();
void setKeyboardHook();
void setKeyboardProc(HOOKPROC KeyboardProc);
void setMouseHook();
void setMouseProc(HOOKPROC MouseProc);

#endif // HOOK_H
