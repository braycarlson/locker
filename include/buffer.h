#ifndef BUFFER_H
#define BUFFER_H

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned char* data;
    int size;
    int head;
    int tail;
} CircularBuffer;

void cleanupBuffer(CircularBuffer* buffer);
CircularBuffer* createBuffer(int size);
void push(CircularBuffer* buffer, unsigned char key);
bool isMatch(CircularBuffer* buffer, unsigned char* hotkey, int length);
unsigned char* asSlice(CircularBuffer* buffer, int* length);

#endif // BUFFER_H
