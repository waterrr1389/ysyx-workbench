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
#include <memory/paddr.h>
/* We use the POSIX regex functions to process regular expressions.
 * Type 'man regex' for more information about POSIX regex functions.
 */
#include <regex.h>
#include <stdint.h>
void set_nemu_state(int state, vaddr_t pc, int halt_ret);

enum {
  TK_NOTYPE = 256,
  TK_PLUS,
  TK_MINUS,
  TK_MUL,
  TK_DIV,
  TK_MOD,
  TK_LP, // left parathesess
  TK_RP,
  TK_EQ,
  TK_DECIMAL,
  TK_HEX,
  TK_REG,
  // 单目负号和解引用不在匹配正则进行判断
  TK_NEG,       // 单目负号
  TK_DEFERENCE, // 解引用
  TK_LE,
  TK_GE,
  TK_NE,
  TK_AND
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
} rules[] = {{" +", TK_NOTYPE},
             {"\\+", TK_PLUS},
             {"==", TK_EQ},
             {"<=", TK_LE},
             {">=", TK_GE},
             {"!=", TK_NE},
             {"\\-", TK_MINUS},
             {"\\*", TK_MUL},
             {"\\/", TK_DIV},
             {"\\(", TK_LP},
             {"\\)", TK_RP},
             {"%", TK_MOD},
             {"^0[xX][0-9A-Fa-f]+", TK_HEX},
             {"&&", TK_AND},
             {"\\$((ra)|(sp)|(gp)|(tp)|(t0)|(t1)|(t2)|(s0)|(s1)|(a0)|(a1)|(a2)|"
              "(a3)|(a4)|(a5)|(a6)|(a7)|(s2)|(s3)|(s4)|(s5)|(s6)|(s7)|(s8)|(s9)"
              "|(s10)|(s11)|(t3)|(t4)|(t5)|(t6)|(pc)|(0))\\b",
              TK_REG},
             {"[0-9]+u", TK_DECIMAL},
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

        // Byte offset from string's start to substring's end.
        int substr_len = pmatch.rm_eo;

        //Log("match rules[%d] = \"%s\" at position %d with len %d: %.*s", i,
        //    rules[i].regex, position, substr_len, substr_len, substr_start);

        // 向前移动到下一个字符串
        position += substr_len;

        /* TODO: Now a new token is recognized with rules[i]. Add codes
         * to record the token in the array `tokens'. For certain types
         * of tokens, some extra actions should be performed.
         */

        switch (rules[i].token_type) {
        case TK_PLUS:
        case TK_MINUS:
        case TK_MUL:
        case TK_DIV:
        case TK_MOD:
        case TK_LP:
        case TK_RP:
        case TK_EQ:
        case TK_NE:
        case TK_LE:
        case TK_GE:
        case TK_DECIMAL:
        case TK_HEX:
        case TK_REG:
          token = tokens + nr_token; // 找到将要存入到tokens数组中的位置
          token->type = rules[i].token_type; // 储存类型
          nr_token++;                        //
          if (ARRLEN(token->str) < substr_len) // 防止token类型自带的buf溢出
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
    // 负号情况：
    // 1. 这是第一个 token（表达式以 `-` 开头）
    // 2. 负号前面是 `(`、`+`、`-`、`*`、`/`
    if (tokens[i].type == TK_MINUS &&
        (i == 0 || tokens[i - 1].type == TK_LP ||
         tokens[i - 1].type == TK_PLUS || tokens[i - 1].type == TK_MINUS ||
         tokens[i - 1].type == TK_MUL || tokens[i - 1].type == TK_DIV || tokens[i - 1].type == TK_AND || 
        tokens[i - 1].type == TK_EQ || tokens[i - 1].type == TK_NE ||
        tokens[i - 1].type == TK_LE || tokens[i - 1].type == TK_GE
        )) {
      tokens[i].type = TK_NEG;
    }
    {}
  }
}

void categorize_dereference() {
  for (int i = 0; i < nr_token; i++) {
    if (tokens[i].type == TK_MUL &&
        // 解引用
        // 1.这是第一个token
        // 2.*号前面是'(', '+', '-', '*', '/'
        (i == 0 || tokens[i - 1].type == TK_LP ||
         tokens[i - 1].type == TK_PLUS || tokens[i - 1].type == TK_MINUS ||
         tokens[i - 1].type == TK_MUL || tokens[i - 1].type == TK_DIV || tokens[i - 1].type == TK_AND || 
        tokens[i - 1].type == TK_EQ || tokens[i - 1].type == TK_NE ||
        tokens[i - 1].type == TK_LE || tokens[i - 1].type == TK_GE
        )) {
      tokens[i].type = TK_DEFERENCE;
    }
  }
}

bool check_expr(int p, int q) { return (p <= q) ? true : false; }

// word_t common.h uint_32 or 64
word_t expr(char *e, bool *success) {
  if (e == NULL) {
      if (success != NULL) *success = false;
      printf("Error: Expression is NULL.\n");
      return 0;
  }
  
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
  case TK_AND:
    return 1;
  case TK_EQ:
  case TK_NE:
    return 2;
  case TK_LE:
  case TK_GE:
    return 3;
  case TK_PLUS:
  case TK_MINUS:
    return 4;
  case TK_MUL:
  case TK_DIV:
  case TK_MOD:
    return 5;
  // 单目运算符优先级最高
  case TK_NEG:
  case TK_DEFERENCE:
    return 6; 
  default:
    return 7; 
  }
}

bool check_parentheses(int p, int q) {
  int close = 0;

  // 首先检查最外层是否有一对匹配括号
  if (tokens[p].type != TK_LP || tokens[q].type != TK_RP) {
    return false; // 最外层没有括号，直接返回 false
  }

  // 遍历所有 token
  for (int i = p; i <= q; i++) {
    int type = tokens[i].type;
    if (type == TK_LP)
      close++;
    if (type == TK_RP)
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

static uint32_t deRef(word_t addr) {
  //无符号
  uint8_t* host_addr = guest_to_host(addr);
  uint32_t val = 0;
  for (int i = 0; i < 4; i++) {
    val += (*host_addr << i*8);
    host_addr++;
  }
  return val;
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
      bool success = false;
      *result = isa_reg_str2val(tokens[p].str, &success);
      if (!success) {
        return EVAL_ERR_INVALID;
      }
      return EVAL_SUCCESS;
    } else if (tokens[p].type == TK_DECIMAL) {
      sscanf(tokens[p].str, "%u", result);
      return EVAL_SUCCESS;
    }
    // 如果不是上述类型,说明表达式非法
    return EVAL_ERR_INVALID;
  } 

  else if (check_parentheses(p, q)) {
    // 如果表达式被一对括号包围，则去掉最外层括号
    return eval(p + 1, q - 1, result);
  } else {
    int op = -1;
    int min_priority = 8; 
    int level = 0;


    // 查找优先级最低的二元运算符
    for (int i = p; i <= q; i++) {
      if (tokens[i].type == TK_LP) level++;
      if (tokens[i].type == TK_RP) level--;
      if (level != 0) continue; // 在括号内，跳过

      int priority = get_priority(tokens[i].type);
      if (priority >= 1 && priority <= 5) { // 仅查找二元运算符
        if (priority <= min_priority) {
          min_priority = priority;
          op = i;
        }
      }
    }

    // 如果没有找到二元运算符 (op == -1), 
    // 说明这应该是一个单目运算 (优先级 6)
    // 单目运算符是右结合的,查找位置最左的
    if (op == -1) {
      level = 0;
      for (int i = p; i <= q; i++) { // 从左到右
        if (tokens[i].type == TK_LP) level++;
        if (tokens[i].type == TK_RP) level--;
        if (level != 0) continue;

        int priority = get_priority(tokens[i].type);
        if (priority == 6) { // 找到单目运算符
          min_priority = priority;
          op = i;
          break; // 找到最左边的就停止
        }
      }
    }
    
    if (op == -1) {
        // 既不是二元也不是单目，也不是括号和单个token，表达式非法
        return EVAL_ERR_INVALID;
    }

    // 如果是单目运算符
    if (min_priority == 6) {
      uint32_t val;
      EvalStatus status = eval(op + 1, q, &val); // 递归右侧
      if (status != EVAL_SUCCESS)
        return status;
      
      switch (tokens[op].type) {
        case TK_NEG:
          *result = (uint32_t)(-((int)val));
          break;
        case TK_DEFERENCE:
          *result = deRef(val);
          break;
        default: return EVAL_ERR_INVALID;
      }
      return EVAL_SUCCESS;
    }

    // 如果是二元运算符 (min_priority 1-5)
    uint32_t val1, val2;
    // 求解左表达式
    EvalStatus status = eval(p, op - 1, &val1);
    if (status != EVAL_SUCCESS)
      return status;
    // 求解右表达式
    status = eval(op + 1, q, &val2);
    if (status != EVAL_SUCCESS)
      return status;

    // 根据主操作符合并结果 
    switch (tokens[op].type) {
    case TK_PLUS:
      *result = val1 + val2;
      break;
    case TK_MINUS:
      *result = val1 - val2;
      break;
    case TK_MUL:
      *result = val1 * val2;
      break;
    case TK_DIV:
      if (val2 == 0)
        return EVAL_ERR_ZERODIV;
      *result = val1 / val2;
      break;
    case TK_MOD:
      *result = val1 % val2;
      break;
    case TK_AND:
      *result = val1 && val2;
      break;
    case TK_EQ:
      *result = (val1 == val2);
      break;
    case TK_NE:
      *result = (val1 != val2);
      break;
    case TK_LE:
      *result = (val1 <= val2);
      break;
    case TK_GE:
      *result = (val1 >= val2);
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

  int correctNum = 0;
  char str[4096] = {0};
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
      // printf("%d line is correct\n", row);
      correctNum++;
    } else {
      printf("Line%d is wrong: val = %d ref = %d\n", row, val1, val2);
    }
    row++;

    memset(str, 0, 4096);
  }
  printf("Correct number: %d\n", correctNum);
  fclose(fp);

  set_nemu_state(NEMU_QUIT, 0, 0);
  return 0;
}
