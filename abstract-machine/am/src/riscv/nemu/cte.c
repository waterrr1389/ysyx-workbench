#include <am.h>
#include <riscv/riscv.h>
#include <klib.h>
#include "context-offset.h"

static Context* (*user_handler)(Event, Context*) = NULL;

static Event decode_event(uintptr_t mcause, uintptr_t a7) {
  Event ev = {0};
  switch (mcause) {
    case 8:
    case 9:
    case 11:
      if (a7 == (uintptr_t)-1)
        ev.event = EVENT_YIELD;
      else
        ev.event = EVENT_SYSCALL;
      break;
    default: ;
  }

  return ev;
}

Context* __am_irq_handle(Context *c) {
  Event ev = decode_event(c->mcause, c->GPR1);
  if (ev.event == EVENT_YIELD || ev.event == EVENT_SYSCALL) {
    c->mepc += 4;
  }

  if (user_handler) {
    c = user_handler(ev, c);
    assert(c != NULL);
  }

  return c;
}

extern void __am_asm_trap(void);

bool cte_init(Context*(*handler)(Event, Context*)) {
  // initialize exception entry
  asm volatile("csrw mtvec, %0" : : "r"(__am_asm_trap));

  // register event handler
  user_handler = handler;

  return true;
}

Context *kcontext(Area kstack, void (*entry)(void *), void *arg) {
  // Place the initial context immediately below the stack's high address.
  uintptr_t context_addr = (uintptr_t)kstack.end - sizeof(Context);
  Context *c = (Context *)context_addr;
  memset(c, 0, sizeof(Context));
  c->mstatus = 0x1800u;
  c->mepc = (uintptr_t)entry;
  (void)arg;
  return c;
}

void yield() {
#ifdef __riscv_e
  asm volatile("li a5, -1; ecall");
#else
  asm volatile("li a7, -1; ecall");
#endif
}

bool ienabled() {
  return false;
}

void iset(bool enable) {
}
