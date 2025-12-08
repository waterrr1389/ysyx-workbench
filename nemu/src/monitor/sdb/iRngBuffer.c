#include "iRingBuffer.h"

iRingBuffer rb;
iRingEntry res[MAX_ENTRIES];

static uint32_t res_head;
static uint32_t res_tail;
static uint32_t res_count;

void iRingBufferInit() {
    memset(&rb, 0, sizeof(iRingBuffer));
    memset(res, 0, sizeof(res));
    rb.head = 0;
    rb.tail = 0;
    res_head = 0;
    res_tail = 0;
    res_count = 0;
}

static uint32_t get_free_bytes() {
    if (res_count == 0) return RING_BUFFER_SIZE;
    
    // rb.tail 指向最旧有效数据的起始位置
    if (rb.head >= rb.tail) {
        return RING_BUFFER_SIZE - (rb.head - rb.tail);
    } else {
        return rb.tail - rb.head;
    }
}

static void drop_oldest() {
    if (res_count == 0) return;

    // 1. 移动 res 的尾部指针
    res_tail = (res_tail + 1) % MAX_ENTRIES;
    res_count--;

    // 2. 更新 buffer 的尾部指针（数据区释放）
    if (res_count > 0) {
        rb.tail = res[res_tail].offset;
    } else {
        rb.tail = rb.head; 
    }
}

void iRingBufferWrite(const void* data, size_t len) {
    if (!data || len == 0 || len > RING_BUFFER_SIZE) return;

    const uint8_t* d = (const uint8_t*)data;

    // 1. 确保条目表有空间
    while (res_count >= MAX_ENTRIES) {
        drop_oldest();
    }

    // 2. 确保数据区有空间 (保留1字节防止重叠歧义)
    while (get_free_bytes() <= len + 1) {
        drop_oldest();
    }

    // 3. 记录元数据
    res[res_head].offset = rb.head;
    res[res_head].len = (uint32_t)len;

    // 4. 写入数据
    for (size_t i = 0; i < len; i++) {
        rb.buffer[rb.head] = d[i];
        rb.head = (rb.head + 1) % RING_BUFFER_SIZE;
    }

    // 5. 更新条目指针
    res_head = (res_head + 1) % MAX_ENTRIES;
    res_count++;
    
    // 若这是第一条数据，tail 需要同步
    if (res_count == 1) {
        rb.tail = res[0].offset; // 这里的逻辑由 drop_oldest 维护，此处仅作保险
        // 实际上 drop_oldest 会正确处理 tail，这里主要防止初始状态
        rb.tail = res[res_tail].offset;
    }
}

void iRingBufferDump() {
    if (res_count == 0) return;

    char temp[RING_BUFFER_SIZE + 1];
    uint32_t idx = res_tail;

    for (uint32_t i = 0; i < res_count; i++) {
        iRingEntry* ent = &res[idx];
        uint32_t r_ptr = ent->offset;
        
        for (uint32_t k = 0; k < ent->len; k++) {
            temp[k] = rb.buffer[r_ptr];
            r_ptr = (r_ptr + 1) % RING_BUFFER_SIZE;
        }
        temp[ent->len] = '\0';
        
        printf("%s\n", temp);

        idx = (idx + 1) % MAX_ENTRIES;
    }
}

bool iRingBufferIsEmpty() {
    return (res_count == 0);
}