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
#define MAX_DEPTH 10
#define BUFFER_SIZE 500000
static char buf[BUFFER_SIZE] = {};
static char code_buf[BUFFER_SIZE + 8192] = {}; // a little larger than `buf`
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
  for (int i = 0; i < num && strlen(buf) < BUFFER_SIZE; i++) {
    strcat(buf, " ");
  }
}

static void gen_num() {
  char num[16];
  // 确保生成的数字被视为无符号整数
  // +1保证生成的数字不包含0
  sprintf(num, "%uu", (uint32_t)rand()%65536 + 1);  // 添加'u'后缀表示无符号整数
  strcat(buf, num);
  gen_space();
}

static void gen_rand_op() {
  uint32_t n = choose(5); // 0-4，增加取模运算符
  char op[5] = {'+', '-', '*', '/', '%'};
  char op_ch = op[n];
  char op_str[2] = {op_ch, '\0'};
  strcat(buf, op_str);
  gen_space();
}


static void gen(char c) {
  char str[2] = {c, '\0'};
  strcat(buf, str);
  gen_space();
}

static void gen_rand_expr(uint32_t depth) {
    switch (choose(3)) {
      case 0: gen_num(); break;
      case 1: gen('('); gen_rand_expr(depth-1); gen(')'); break;
      default: gen_rand_expr(depth-1); gen_rand_op(); gen_rand_expr(depth-1); break;
    }
}

void initRamdon() {
  int seed = time(0);
  srand(seed);
}

int main(int argc, char *argv[]) {
  initRamdon();

  int numOfExpr = 1;
  if (argc > 1) {
    sscanf(argv[1], "%d", &numOfExpr);
  }

  int i;
  for (i = 0; i < numOfExpr; i++) {
    buf[0] = '\0';
    gen_rand_expr(MAX_DEPTH);

    //替换code_format中的%s
    sprintf(code_buf, code_format, buf);

    FILE *fp = fopen("/tmp/.code.c", "w");
    assert(fp != NULL);
    fputs(code_buf, fp);
    fclose(fp);

    //将处零警告转换为错误,通过检查返回值
    int ret = system("gcc -Wall -Werror /tmp/.code.c -o /tmp/.expr");
    if (ret != 0) { 
      i--;
      continue;
    }

    fp = popen("/tmp/.expr", "r");
    assert(fp != NULL);

    int result;
    ret = fscanf(fp, "%d", &result);
    pclose(fp);

    printf("%u %s\n", result, buf);
  }
  return 0;
}
