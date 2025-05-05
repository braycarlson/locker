#ifndef LOCKER_H
#define LOCKER_H

#include <stdbool.h>
#include <stdlib.h>

#include "../include/buffer.h"
#include "../include/tray.h"

typedef struct {
    CircularBuffer* queue;
    Tray* tray;
    unsigned char* lockHotkey;
    unsigned char* unlockHotkey;
    bool isLocked;
} Locker;

void cleanupLocker(Locker* locker);
void createLocker(HWND hwnd);
void toggleLock(Locker* locker, bool lock);

#endif // LOCKER_H
