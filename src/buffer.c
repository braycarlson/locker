#include "../include/buffer.h"

CircularBuffer* createBuffer(int size) {
    CircularBuffer* buffer = (CircularBuffer*)malloc(sizeof(CircularBuffer));
    buffer->data = (unsigned char*)malloc(size * sizeof(unsigned char));
    buffer->size = size;
    buffer->head = 0;
    buffer->tail = 0;

    return buffer;
}

void push(CircularBuffer* buffer, unsigned char key) {
    buffer->data[buffer->tail] = key;
    buffer->tail = (buffer->tail + 1) % buffer->size;

    if (buffer->tail == buffer->head) {
        buffer->head = (buffer->head + 1) % buffer->size;
    }
}

unsigned char* asSlice(CircularBuffer* buffer, int* length) {
    if (buffer->tail >= buffer->head) {
        *length = buffer->tail - buffer->head;
    } else {
        *length = buffer->size - buffer->head + buffer->tail;
    }

    unsigned char* slice = (unsigned char*)malloc(*length * sizeof(unsigned char));

    if (buffer->tail >= buffer->head) {
        memcpy(slice, buffer->data + buffer->head, *length);
    } else {
        int section = buffer->size - buffer->head;
        memcpy(slice, buffer->data + buffer->head, section);
        memcpy(slice + section, buffer->data, buffer->tail);
    }

    return slice;
}

bool isMatch(CircularBuffer* buffer, unsigned char* hotkey, int maximum) {
    int length;
    unsigned char* slice = asSlice(buffer, &length);

    if (length < maximum) {
        free(slice);
        return false;
    }

    bool match = true;

    for (int i = length - maximum; i < length; i++) {
        if (slice[i] != hotkey[i - (length - maximum)]) {
            match = false;
            break;
        }
    }

    free(slice);
    return match;
}

void cleanupBuffer(CircularBuffer* buffer) {
    if (buffer) {
        free(buffer->data);
        free(buffer);
    }
}
