#include "callstack.h"

static int depth; // 栈中的元素个数
static CallStackNode *stack_top = NULL;

void init_stack() { stack_top = malloc(sizeof(CallStackNode)); }

// 功能：创建一个新节点，填充信息，并将其放到链表头部
void stack_push(word_t pc, word_t target, const char *name) {
  // 1. 分配内存 (使用 malloc)
  CallStackNode *new_node = malloc(sizeof(CallStackNode));
  Assert(new_node != NULL, "Memory allocation failed");

  // 2. 填充数据
  new_node->pc = pc;
  new_node->target = target;
  strncpy(new_node->func_name, name, FUNC_LENGH - 1);

  // 3. 链表插入操作 (更新 next 和 stack_top)
  if (stack_top == NULL || depth == 0) {
    stack_top = new_node;
  } else {
    new_node->next = stack_top;
    stack_top = new_node;
  }
  depth++;
}

// 功能：移除链表头部的节点，并释放内存
// 返回值：如果栈为空，可以处理错误或忽略
void stack_pop() {
  if (stack_top == NULL || depth == 0)
    return;

  // 1. 保存当前栈顶的指针，以便稍后 free
  CallStackNode *temp = stack_top;

  // 2. 更新 stack_top 指向下一个节点
  // TODO: 移动 stack_top
  stack_top = stack_top->next;
  depth--;
  // 3. 释放旧的栈顶内存
  free(temp);
}

// 辅助函数：计算当前栈深度，用于打印缩进
int get_stack_depth() { return depth; }

// 辅助函数:获取当前栈顶指针
CallStackNode *get_stack_top() { return stack_top; }