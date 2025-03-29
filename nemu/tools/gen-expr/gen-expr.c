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

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <assert.h>
#include <string.h>

// this should be enough
#define MAX_DEPTH 5
static char buf[65536] = {};
static char code_buf[65536 + 128] = {}; // a little larger than `buf`
static char *code_format =
"#include <stdio.h>\n"
"int main() { "
"  unsigned result = %s; "  // 确保结果是无符号的
"  printf(\"%%u\", result); "
"  return 0; "
"}";

static uint32_t choose(uint32_t n) {
  return ((uint32_t)rand()) % n;
}

static void gen_space() {
  // 改进空格生成逻辑，更清晰且有更好的随机性
  int num = choose(4); // 0-3
  for (int i = 0; i < num && strlen(buf) < 60000; i++) {
    strcat(buf, " ");
  }
}

static void gen_num() {
  char num[16];
  // 确保生成的数字被视为无符号整数
  sprintf(num, "%uu", (uint32_t)rand()%1000 + 1);  // 添加'u'后缀表示无符号整数
  strcat(buf, num);
  gen_space();
}

static void gen_rand_op() {
  uint32_t n = choose(5); // 0-4，增加取模运算符
  char op[5] = {'+', '-', '*', '/'};
  char op_ch = op[n];
  char op_str[2] = {op_ch, '\0'};
  strcat(buf, op_str);
  gen_space();
}

// 检查表达式是否可能导致除零错误
static int check_div_mod_by_zero(char *expr) {
  // 简单检查是否有除零或模零的情况
  char *p = expr;
  while (*p) {
    // 检查是否有除以0或模0的情况
    // 注意需要考虑0u这种无符号表示
    if ((*p == '/' || *p == '%') && 
        ((*(p+1) == '0' && (*(p+2) == 'u' || *(p+2) == 'U')) || 
         (*(p+1) == '0' && 
          (*(p+2) == '\0' || *(p+2) == ' ' || *(p+2) == ')' || 
           *(p+2) == '+' || *(p+2) == '-' || *(p+2) == '*' || 
           *(p+2) == '/' || *(p+2) == '%')))) {
      return 1; // 可能有除零或模零
    }
    p++;
  }
  return 0; // 没有检测到除零或模零
}

static void gen(char c) {
  char str[2] = {c, '\0'};
  strcat(buf, str);
  gen_space();
}

static void gen_rand_expr(uint32_t depth) {
  // 增加表达式长度检查，避免生成过长表达式
  if (depth <= 0 || strlen(buf) > 60000) {
    gen_num();
    return;
  }
  else {
    // 检查当前表达式长度，如果接近限制则直接生成数字
    if (strlen(buf) > 55000) {
      gen_num();
      return;
    }
    
    switch (choose(3)) {
      case 0: gen_num(); break;
      case 1: gen('('); gen_rand_expr(depth-1); gen(')'); break;
      default: gen_rand_expr(depth-1); gen_rand_op(); gen_rand_expr(depth-1); break;
    }
  }
}

int main(int argc, char *argv[]) {
  int seed = time(0);
  srand(seed);
  int loop = 1;
  if (argc > 1) {
    sscanf(argv[1], "%d", &loop);
  }
  int i;
  for (i = 0; i < loop; i ++) {
    buf[0] = '\0';
    gen_rand_expr(MAX_DEPTH);

    // 检查是否有除零或模零的情况
    if (check_div_mod_by_zero(buf)) {
      i--; // 重新生成表达式
      continue;
    }

    sprintf(code_buf, code_format, buf);

    FILE *fp = fopen("/tmp/.code.c", "w");
    assert(fp != NULL);
    fputs(code_buf, fp);
    fclose(fp);

    int ret = system("gcc /tmp/.code.c -o /tmp/.expr");
    if (ret != 0) continue;

    fp = popen("/tmp/.expr", "r");
    assert(fp != NULL);

    int result;
    ret = fscanf(fp, "%d", &result);
    pclose(fp);

    printf("%u %s\n", result, buf);
  }
  return 0;
}
