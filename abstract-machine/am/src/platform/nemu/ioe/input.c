#include <am.h>
#include <nemu.h>

#define KEYDOWN_MASK 0x8000

void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  static uint32_t current = -1, prev = -1;
  if (prev == current && current == -1) { // initial
    current = inb(KBD_ADDR);
    kbd->keydown = true;
    kbd->keycode = current;
  } else {
    current = inb(KBD_ADDR);
    if (prev == current) { // same key
      kbd->keydown = true;
      kbd->keycode = current;
    } else { // another key
      kbd->keydown = false;
      kbd->keycode = prev;
    }
  }
  prev = current;
}
