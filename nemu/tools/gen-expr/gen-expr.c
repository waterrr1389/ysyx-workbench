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
"  unsigned result = %s; "
"  printf(\"%%u\", result); "
"  return 0; "
"}";

static uint32_t choose(uint32_t n) {
  return ((uint32_t)rand()) % n;
}

static void gen_space() {
  int num = choose(3);
  if (num != 1) return;
  for (int i = 0; i < num && strlen(buf) < 60000; i++) {
    strcat(buf, " ");
  }
}

static void gen_num() {
  char num[16];
  sprintf(num, "%u", (uint32_t)rand()%1000 + 1);
  strcat(buf, num);
  gen_space();
}

static void gen_rand_op() {
  uint32_t n = choose(4); //0-3
  char op[4] = {'+', '-', '*', '/'};
  char op_ch = op[n];
  char op_str[2] = {op_ch, '\0'};
  strcat(buf, op_str);
  //if (n == 3) gen_num();
  gen_space();
}

static void gen(char c) {
  char str[2] = {c, '\0'};
  strcat(buf, str);
  gen_space();
}

static void gen_rand_expr(uint32_t depth) {
  if (depth <= 0 || strlen(buf) > 60000) {
    gen_num();
    return;
  }
  else {
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