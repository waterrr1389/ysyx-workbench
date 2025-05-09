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
void set_nemu_state(int state, vaddr_t pc, int halt_ret);

enum {
  TK_NOTYPE = 256,
  TK_EQ,
  TK_DECIMAL,
  TK_NEG, // 单目负号
  TK_HEX,
  TK_REG,
  TK_DEFERENCE, // 解引用
  /* TODO: Add more token types */
};

typedef enum {
  EVAL_SUCCESS = 0, // 成功
  EVAL_ERR_NULL,    // 空表达式错误
  EVAL_ERR_INVALID, // 非法节点错误
  EVAL_ERR_ZERODIV  // 除零错误
} EvalStatus;

static struct rule {
  const char *regex;
  int token_type;
} rules[] = {{" +", TK_NOTYPE}, // spaces
             {"\\+", '+'},      // plus
             {"==", TK_EQ},     // equal
             {"\\-", '-'},      // 二元减法运算符
             {"\\*", '*'},      // multiply
             {"\\/", '/'},      // division
             {"\\(", '('},          {"\\)", ')'},
             {"\\%", '%'},       {"^0[xX][0-9A-Fa-f]+", TK_HEX},
             {"\\$[0-9]+", TK_REG}, {"[0-9]+u", TK_DECIMAL},
             {"[0-9]+", TK_DECIMAL}};

#define NR_REGEX ARRLEN(rules)

static regex_t re[NR_REGEX] = {};
EvalStatus eval(int p, int q, uint32_t *result);
void categorize_minus();

/* Rules are used for many times.
 * Therefore we compile them only once before any usage.
 */
void init_regex() {
  int i;
  char error_msg[128];
  int ret;

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
        case '%':
        case '(':
        case ')':
        case TK_EQ:
        case TK_DECIMAL:
        case TK_HEX:
        case TK_REG:
          token = tokens + nr_token;
          token->type = rules[i].token_type;
          nr_token++;
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
      }
    }
  }
}

void categorize_dereference() {
  for (int i = 0; i < nr_token; i++) {
    if (tokens[i].type == '*' &&
        (i == 0 || tokens[i - 1].type == '(' || tokens[i - 1].type == '+' ||
         tokens[i - 1].type == '-' || tokens[i - 1].type == '*' ||
         tokens[i - 1].type == '/')) {
      tokens[i].type = TK_DEFERENCE;
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

  /* 根据上下文区分负号与二元减法 */
  categorize_minus();
  categorize_dereference();

  if (!check_expr(0, nr_token - 1)) {
    *success = false;
    return 0;
  }

  uint32_t result;
  EvalStatus status = eval(0, nr_token - 1, &result);
  if (status != EVAL_SUCCESS) {
    *success = false;
    if (status == EVAL_ERR_ZERODIV) {
      printf("Error: Division by zero!\n");
    } else if (status == EVAL_ERR_INVALID) {
      printf("Error: Invalid expression!\n");
    }
    return 0;
  }
  *success = true;
  return result;
}

int get_priority(int type) {
  switch (type) {
  case '+':
  case '-':
    return 1;
  case '*':
  case '/':
  case '%':
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

EvalStatus eval(int p, int q, uint32_t *result) {
  if (p > q) {
    return EVAL_ERR_INVALID;
  } else if (p == q) {
    // 单个token,为数字或寄存器
    if (tokens[p].type == TK_HEX) {
      sscanf(tokens[p].str, "%x", result);
      return EVAL_SUCCESS;
    } else if (tokens[p].type == TK_REG) {
      *result = isa_reg_str2val(tokens[p].str + 1, NULL);
      return EVAL_SUCCESS;
    } else if (tokens[p].type == TK_DECIMAL) {
      sscanf(tokens[p].str, "%u", result);
      return EVAL_SUCCESS;
    }
    return EVAL_ERR_INVALID;
  } else if (tokens[p].type == TK_NEG) {
    /* 处理单目负号 */
    uint32_t tmp;
    EvalStatus status = eval(p + 1, q, &tmp);
    if (status != EVAL_SUCCESS)
      return status;
    *result = (uint32_t)(-((int)tmp));
    return EVAL_SUCCESS;
  } else if (check_parentheses(p, q)) {
    /* 如果表达式被一对括号包围，则去掉最外层括号 */
    return eval(p + 1, q - 1, result);
  } else {
    int op = -1;
    int min_priority = 4; // 初始值设置为比最高优先级还高
    int level = 0;
    /* 找出最主要的运算符，即处于最外层且优先级最低的运算符 */
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
    if (op == -1)
      return EVAL_ERR_INVALID;
    uint32_t val1, val2;
    EvalStatus status = eval(p, op - 1, &val1);
    if (status != EVAL_SUCCESS)
      return status;
    status = eval(op + 1, q, &val2);
    if (status != EVAL_SUCCESS)
      return status;
    switch (tokens[op].type) {
    case '+':
      *result = val1 + val2;
      break;
    case '-':
      *result = val1 - val2;
      break;
    case '*':
      *result = val1 * val2;
      break;
    case '/':
      if (val2 == 0)
        return EVAL_ERR_ZERODIV;
      *result = val1 / val2;
      break;
    case '%':
      *result = val1 % val2;
      break;
    default:
      return EVAL_ERR_INVALID;
    }
    return EVAL_SUCCESS;
  }
}

int test() {
  FILE *fp =
      fopen("/home/waterrr/ysyx-workbench/nemu/tools/gen-expr/input", "r");
  Assert(fp, "%s\n", "Failed to open file");

  char str[2048] = {0};
  char *exp = 0;
  char *pos = 0;
  int row = 1;
  word_t val1, val2;
  bool success = true;

  while (fgets(str, sizeof(str), fp) != NULL) {
    // 解析标准答案的值
    if (sscanf(str, "%u", &val2) != 1) {
      printf("%d line sscanf() failed\n", row);
      continue;
    }

    // 获取表达式字符串
    pos = strchr(str, ' ');
    if (pos) {
      exp = pos + 1;
      char *newline = strchr(exp, '\n');
      if (newline) {
        *newline = '\0';
      }
    } else {
      printf("%d line getexpr failed\n", row);
      continue;
    }

    // 计算表达式的值
    val1 = expr(exp, &success);
    if (!success) {
      printf("%d line expr() failed\n", row);
      continue;
    }

    // 比较两个结果
    if (val1 == val2) {
      printf("%d line is correct\n", row);
    } else {
      printf("%d line is wrong\n", row);
    }
    row++;

    memset(str, 0, 2048);
  }

  fclose(fp);
  
  set_nemu_state(NEMU_QUIT, 0, 0);
  return 0;
}
