#include <am.h>
#include <nemu.h>

#define SYNC_ADDR (VGACTL_ADDR + 4)

void __am_gpu_init() {
}

void __am_gpu_config(AM_GPU_CONFIG_T *cfg) {
  *cfg = (AM_GPU_CONFIG_T) {
    .present = true, .has_accel = false,
    .width = 400, .height = 300,
    .vmemsz = 400*300*4
  };
}

void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
  uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;
  uint32_t screen_w = inl(VGACTL_ADDR) >> 16;    // 屏幕总宽度
  uint32_t *pixels = (uint32_t *)ctl->pixels;
  
  int x = ctl->x, y = ctl->y, w = ctl->w, h = ctl->h;
  
  for (int j = 0; j < h; j++) {                  // 第 j 行（0-based）
    for (int k = 0; k < w; k++) {                // 第 k 列
      // 目标位置：屏幕 (x+k, y+j)
      fb[(y + j) * screen_w + (x + k)] = pixels[j * w + k];
    }
  }
  
  if (ctl->sync) {
    outl(SYNC_ADDR, 1);
  }
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  status->ready = true;
}
