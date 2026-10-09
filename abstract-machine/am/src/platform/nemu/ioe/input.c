#include <am.h>
#include <nemu.h>

#define KEYDOWN_MASK 0x8000

void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  uint32_t key = inw(KBD_ADDR);
  if (key & 0x8000u) {
    kbd->keydown = true;
    key &= ~0x8000u;
  } else {
    kbd->keydown = false;
  }
  kbd->keycode = key;
}
