#pragma once
#include "ftrace.h"
#include <common.h>

typedef struct CallStackNode {
  word_t pc;                  // 调用指令的地址 (jal 的地址)
  word_t target;              // 调用的目标地址
  char func_name[FUNC_LENGH]; // 函数名
  struct CallStackNode *next; // 指向下一个节点的指针
} CallStackNode;

void init_stack();
int get_stack_depth();
CallStackNode *get_stack_top();
void stack_push(word_t pc, word_t target, const char *name);
void stack_pop();