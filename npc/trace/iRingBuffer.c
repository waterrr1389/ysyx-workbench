#include "trace/iRingBuffer.h"

#include <stdio.h>
#include <string.h>

static iRingBuffer rb;
static iRingEntry entries[MAX_ENTRIES];

static uint32_t entry_head;
static uint32_t entry_tail;
static uint32_t entry_count;

void iRingBufferInit(void) {
  memset(&rb, 0, sizeof(rb));
  memset(entries, 0, sizeof(entries));
  rb.head = 0;
  rb.tail = 0;
  entry_head = 0;
  entry_tail = 0;
  entry_count = 0;
}

static uint32_t get_free_bytes(void) {
  if (entry_count == 0) {
    return RING_BUFFER_SIZE;
  }

  if (rb.head >= rb.tail) {
    return RING_BUFFER_SIZE - (rb.head - rb.tail);
  }
  return rb.tail - rb.head;
}

static void drop_oldest(void) {
  if (entry_count == 0) {
    return;
  }

  entry_tail = (entry_tail + 1) % MAX_ENTRIES;
  entry_count--;

  if (entry_count > 0) {
    rb.tail = entries[entry_tail].offset;
  } else {
    rb.tail = rb.head;
  }
}

void iRingBufferWrite(const void* data, size_t len) {
  if (data == NULL || len == 0 || len > RING_BUFFER_SIZE) {
    return;
  }

  const uint8_t* src = (const uint8_t*)data;

  while (entry_count >= MAX_ENTRIES) {
    drop_oldest();
  }

  while (get_free_bytes() <= len + 1) {
    drop_oldest();
  }

  entries[entry_head].offset = rb.head;
  entries[entry_head].len = len;

  for (size_t i = 0; i < len; i++) {
    rb.buffer[rb.head] = src[i];
    rb.head = (rb.head + 1) % RING_BUFFER_SIZE;
  }

  entry_head = (entry_head + 1) % MAX_ENTRIES;
  entry_count++;

  if (entry_count == 1) {
    rb.tail = entries[entry_tail].offset;
  }
}

void iRingBufferDump(void) {
  if (entry_count == 0) {
    return;
  }

  char temp[RING_BUFFER_SIZE + 1];
  uint32_t idx = entry_tail;

  for (uint32_t i = 0; i < entry_count; i++) {
    iRingEntry* entry = &entries[idx];
    uint32_t read_ptr = entry->offset;

    for (uint32_t k = 0; k < entry->len; k++) {
      temp[k] = rb.buffer[read_ptr];
      read_ptr = (read_ptr + 1) % RING_BUFFER_SIZE;
    }
    temp[entry->len] = '\0';
    printf("%s\n", temp);

    idx = (idx + 1) % MAX_ENTRIES;
  }
}

bool iRingBufferIsEmpty(void) {
  return entry_count == 0;
}
