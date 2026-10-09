#include <am.h>
#include <nemu.h>

#define KEYDOWN_MASK 0x8000

void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  static uint32_t current = AM_KEY_NONE, prev = AM_KEY_NONE;
  current = inb(KBD_ADDR);
  if (prev != AM_KEY_NONE) {
    kbd->keydown = false;
    kbd->keycode = prev;
  } else {
    kbd->keydown = true;
    kbd->keycode = current;
  }
  prev = current;
  current = AM_KEY_NONE;
}
