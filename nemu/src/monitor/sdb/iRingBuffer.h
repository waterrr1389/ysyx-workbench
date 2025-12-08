#pragma once
#include <common.h>
#include <stdint.h>

#define RING_BUFFER_SIZE 4096 
#define MAX_ENTRIES 32	

// #define RING_BUFFER_SIZE 2048

typedef struct {
    char buffer[RING_BUFFER_SIZE];
    int head;
	int tail;
} iRingBuffer;

typedef struct {
	int offset;
	size_t len;
} iRingEntry;

void iRingBufferInit();
void iRingBufferWrite(const void* data, size_t len);
void iRingBufferDump();
bool iRingBufferIsEmpty();