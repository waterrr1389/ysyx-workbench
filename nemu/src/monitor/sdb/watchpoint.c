/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "watchpoint.h"
#include "sdb.h"
#include "utils.h"

#define NR_WP 32

static WP wp_pool[NR_WP] = {};
static WP *head = NULL, *free_ = NULL;
//head 已使用的, free_未使用的

WP* get_watchpoint_head() {
  return head;
}

void init_wp_pool() {
  int i;
  for (i = 0; i < NR_WP; i ++) {
    wp_pool[i].NO = i;
    //指向下一个节点 或者 (在结尾时)指向链表末尾
    wp_pool[i].next = (i == NR_WP - 1 ? NULL : &wp_pool[i + 1]);
  }

  head = NULL;
  free_ = wp_pool;
}

/* TODO: Implement the functionality of watchpoint */
WP* new_wp() {
  if (free_ == NULL) {
    printf("No enough watchpoints.\n");
    assert(0);
  }
  WP *wp = free_;
  free_ = free_->next;

  //头插法加入head
  wp->next = head;
  head = wp;
  return wp;
}

void free_wp(WP *wp) {
  if (wp == NULL) {
    printf("Watchpoint to free is NULL.\n");
    return;
  }
  if (head == wp) {
    head = head->next;
  } else {
    WP *p;
    for (p = head; p != NULL; p = p->next) {
      if (p->next == wp) {
        p->next = wp->next;
        break;
      }
    }
  }
  wp->next = free_;
  free_ = wp;
}

WP* get_wp(int NO) {
  WP *p;
  for (p = head; p != NULL; p = p->next) {
    if (p->NO == NO) {
      return p;
    }
  }
  return NULL;
}

void watchpoint_display() {
  WP *p;
  for (p = head; p != NULL; p = p->next) {
    printf("Watchpoint %d: %s = %08x\n", p->NO, p->str, p->value);
  }
}

void check_watchpoints() {
  WP *wp = get_watchpoint_head();
  while (wp != NULL) {
    uint32_t origin_val, curr_val;
    bool success;
    origin_val = wp->value;
    curr_val = expr(wp->str, &success);
    if (!success) {
      printf("Error evaluating watchpoint expression '%s'\n", wp->str);
    } else {
      if (origin_val != curr_val) {
        printf("Watchpoint %d: %s changed from %08x to %08x\n",
                   wp->NO, wp->str, origin_val, curr_val);
        // if state == NEMU_END, do not change it
        if (nemu_state.state != NEMU_END) nemu_state.state = NEMU_STOP; 
        wp->value = curr_val;
      }
    }
    wp = wp->next;
  }
}