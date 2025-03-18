/***************************************************************************************
 * Copyright (c) 2014-2024 Zihao Yu, Nanjing University
 *
 * NEMU is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan
 *PSL v2. You may obtain a copy of Mulan PSL v2 at:
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY
 *KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
 *NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 *
 * See the Mulan PSL v2 for more details.
 ***************************************************************************************/

#include <isa.h>

/* We use the POSIX regex functions to process regular expressions.
 * Type 'man regex' for more information about POSIX regex functions.
 */
#include <regex.h>

enum {
  TK_NOTYPE = 256,
  TK_EQ,
  TK_DECIMAL,
  TK_NEG,      //单目负号
  /* TODO: Add more token types */
};

static struct rule {
  const char *regex;
  int token_type;
} rules[] = {
    {" +", TK_NOTYPE}, // spaces
    {"\\+", '+'},      // plus
    {"==", TK_EQ},     // equal
    {"\\-", '-'},      // 二元减法运算符
    {"\\*", '*'},      // multiply
    {"\\/", '/'},      // division
    {"\\(", '('}, 
    {"\\)", ')'}, 
    {"[0-9]+", TK_DECIMAL}
};

#define NR_REGEX ARRLEN(rules)

static regex_t re[NR_REGEX] = {};
uint32_t eval(int p, int q);
void categorize_minus();
/* Rules are used for many times.
 * Therefore we compile them only once before any usage.
 */
void init_regex() {
  int i;
  char error_msg[128];
  int ret;

  categorize_minus();

  for (i = 0; i < NR_REGEX; i++) {
    ret = regcomp(&re[i], rules[i].regex, REG_EXTENDED);
    if (ret != 0) {
      regerror(ret, &re[i], error_msg, 128);
      panic("regex compilation failed: %s\n%s", error_msg, rules[i].regex);
    }
  }
}

typedef struct token {
  int type;
  char str[32];
} Token;

static Token tokens[512] __attribute__((used)) = {};
static int nr_token __attribute__((used)) = 0;

static bool make_token(char *e) {
  int position = 0;
  int i;
  regmatch_t pmatch;
  Token *token;
  nr_token = 0;

  while (e[position] != '\0') {
    /* Try all rules one by one. */
    for (i = 0; i < NR_REGEX; i++) {
      if (regexec(&re[i], e + position, 1, &pmatch, 0) == 0 &&
          pmatch.rm_so == 0) {
        char *substr_start = e + position;
        int substr_len = pmatch.rm_eo;

        Log("match rules[%d] = \"%s\" at position %d with len %d: %.*s", i,
            rules[i].regex, position, substr_len, substr_len, substr_start);

        position += substr_len;

        /* TODO: Now a new token is recognized with rules[i]. Add codes
         * to record the token in the array `tokens'. For certain types
         * of tokens, some extra actions should be performed.
         */

        switch (rules[i].token_type) {
        case '+':
        case '-':
        case '*':
        case '/':
        case '(':
        case ')':
        case TK_EQ:
        case TK_DECIMAL:
          token = tokens + nr_token;
          token->type = rules[i].token_type;
          nr_token++;
          // Assert(((ARRLEN(token->str)-1) >= substr_len), "%s\n", "String
          // Buffer Overflow.");
          if (ARRLEN(token->str) < substr_len)
            return false;
          strncpy(token->str, substr_start, substr_len);
          token->str[substr_len] = '\0';
          break;
        case TK_NOTYPE:
          break;
        default:
          Log("Unrecognized token at position: %d with len: %d", position,
              substr_len);
        }

        break;
      }
    }

    if (i == NR_REGEX) {
      printf("no match at position %d\n%s\n%*.s^\n", position, e, position, "");
      return false;
    }
  }

  return true;
}

void categorize_minus() {
  for (int i = 0; i < nr_token; i++) {
      if (tokens[i].type == '-') {
          // 负号情况：
          // 1. 这是第一个 token（表达式以 `-` 开头）
          // 2. 负号前面是 `(`、`+`、`-`、`*`、`/`
          if (i == 0 || tokens[i - 1].type == '(' || tokens[i - 1].type == '+' ||
              tokens[i - 1].type == '-' || tokens[i - 1].type == '*' ||
              tokens[i - 1].type == '/') {
              tokens[i].type = TK_NEG;
          } else {
              tokens[i].type = '-';
          }
      }
  }
}

bool check_expr(int p, int q) { return true; }

// word_t common.h uint_32 or 64
word_t expr(char *e, bool *success) {
  if (!make_token(e)) {
    *success = false;
    return 0;
  }

  // 检查表达式合法性
  if (check_expr(0, nr_token - 1))
    return eval(0, nr_token - 1);
  else
    return 0;
}

int get_priority(int type) {
  switch (type) {
  case '+':
  case '-':
    return 1;
  case '*':
  case '/':
    return 2;
  default:
    return 3;
  }
}

bool check_parentheses(int p, int q) {
  int close = 0;

  // 首先检查最外层是否有一对匹配括号
  if (tokens[p].type != '(' || tokens[q].type != ')') {
    return false; // 最外层没有括号，直接返回 false
  }

  // 遍历所有 token
  for (int i = p; i <= q; i++) {
    int type = tokens[i].type;
    if (type == '(')
      close++;
    if (type == ')')
      close--;

    // 一旦右括号比左括号多，说明不匹配
    if (close < 0)
      return false;

    // 如果中途括号完全闭合了，说明最外层的括号不匹配
    if (close == 0 && i != p && i != q)
      return false;
  }

  // 括号未闭合
  if (close != 0)
    return false;

  return true;
}

uint32_t eval(int p, int q) {
  if (p > q) {
    /* Bad expression */
    panic("%s\n", "Bad expression");
  } else if (p == q) {
    /* Single token.
     * For now this token should be a number.
     * Return the value of the number.
     */
    if (tokens[p].type == TK_DECIMAL) {
      uint32_t val;
      sscanf(tokens[p].str, "%u", &val);
      return val;
    }
    return 0;
  } else if (check_parentheses(p, q)) {
    /* The expression is surrounded by a matched pair of parentheses.
     * If that is the case, just throw away the parentheses.
     */
    return eval(p + 1, q - 1);
  } else {
    int op = -1;
    int min_priority = 3;
    int level = 0;
    for (int i = p; i <= q; i++) {
      if (tokens[i].type == '(')
        level++;
      if (tokens[i].type == ')')
        level--;

      if (level == 0) {
        int priority = get_priority(tokens[i].type);
        if (priority <= min_priority) {
          min_priority = priority;
          op = i;
        }
      }
    }

    uint32_t val1 = eval(p, op - 1);
    uint32_t val2 = eval(op + 1, q);
    uint32_t op_type = tokens[op].type;

    switch (op_type) {
    case '+':
      return val1 + val2;
    case '-':
      return val1 - val2;
    case '*':
      return val1 * val2;
    case '/':
      Assert(val2 == 0, "%s\n", "Zero Division");
      return val1 / val2;
    default:
      panic("%s\n", "Unknown operator type");
    }
  }
}

int test() {
  FILE *fp =
      fopen("/home/waterrr/ysyx-workbench/nemu/tools/gen-expr/input", "r");
  Assert(fp, "%s\n", "Failed to open file");

  char str[2048] = {0};
  char exp[2048] = {0};
  int row = 1;
  word_t val1, val2;
  bool success = true;

  while (fgets(str, sizeof(str), fp) != NULL) {
    // 解析标准答案的值
    if (sscanf(str, "%u", &val2) != 1) {
      printf("%d line sscanf() failed\n", row);
      continue;
    }

    // 找到第一个 '\n'
    char *pos = strchr(str, '\n');  
    if (pos) {
        *pos = '\0';  // 替换为 '\0'      
    } else {
      printf("%d line getexpr failed\n", row);
      continue;
    }

    // 计算表达式的值
    str[strlen(exp) - 1] = '\0';
    val1 = expr(exp, &success);
    if (!success) {
      printf("%d line expr() failed\n", row);
      continue;
    }

    // 比较两个结果
    if (val1 == val2) {
      printf("%d line is correct\n", row);
    } else {
      printf("%d line is incorrect\n", row);
    }
    row++;

    memset(str, 0, 2048);
    memset(exp, 0, 2048);
  }

  fclose(fp);
  return 0;
}
