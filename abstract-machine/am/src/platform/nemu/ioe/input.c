#include <am.h>
#include <nemu.h>

#define KEYDOWN_MASK 0x8000

void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  static uint32_t current = AM_KEY_NONE, prev = AM_KEY_NONE;
  current = inb(KBD_ADDR);
  if (prev == AM_KEY_NONE) { // initial
    kbd->keydown = true;
    kbd->keycode = current;
  } else if (prev == current) { // same key
    kbd->keydown = true;
    kbd->keycode = current;
  } else { // another key
    kbd->keydown = false;
    kbd->keycode = prev;
  }
  prev = current;
}
