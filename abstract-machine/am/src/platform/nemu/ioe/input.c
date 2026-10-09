#include <am.h>
#include <nemu.h>

#define KEYDOWN_MASK 0x8000

void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  uint32_t key = inb(KBD_ADDR);
  if (key & 0x8000) {
    kbd->keydown = false;
  } else {
    kbd->keydown = true;
  }
  kbd->keycode = key;
}
