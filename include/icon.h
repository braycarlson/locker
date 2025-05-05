#ifndef ICON_H
#define ICON_H

#include <stdbool.h>
#include <windows.h>

#include "../include/resource.h"

HICON loadIconFromResources(HINSTANCE hInstance, bool isLocked);

#endif // ICON_H
