#pragma once

#include "base/common.h"

#define FUNC_LENGH 64

typedef struct CallStackNode {
  word_t pc;
  word_t target;
  char func_name[FUNC_LENGH];
  struct CallStackNode* next;
} CallStackNode;

#ifdef __cplusplus
extern "C" {
#endif

void init_stack(void);
int get_stack_depth(void);
CallStackNode* get_stack_top(void);
void stack_push(word_t pc, word_t target, const char* name);
void stack_pop(void);

#ifdef __cplusplus
}
#endif
