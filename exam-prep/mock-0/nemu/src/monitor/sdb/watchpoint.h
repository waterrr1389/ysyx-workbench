#ifndef __WATCHPOINT_H__
#define __WATCHPOINT_H__

#include <common.h>

typedef struct watchpoint {
  int NO;
  struct watchpoint *next;
  char str[64];
  uint32_t value;
  /* TODO: Add more members if necessary */

} WP; // 单向链表

WP* new_wp();
void free_wp(WP *wp);
WP* get_wp(int NO);
void watchpoint_display();
WP* get_watchpoint_head();
void check_watchpoints();

#endif