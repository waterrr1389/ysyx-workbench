#include <stdint.h>
#include <stdint.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <assert.h>
#include <string.h>

#define MAX_DEPTH 11
// 这个缓冲区已经绰绰有余且非常安全
#define BUFFER_SIZE 100000 
static char buf[BUFFER_SIZE] = {};
// buf_ptr 指向 buf 中下一个可以写入字符的位置
static char *buf_ptr; 
static char code_buf[BUFFER_SIZE + 128] = {};
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

static void append(const char *s, size_t len) {
    // 检查剩余空间是否足够
    if (buf_ptr + len + 1 > buf + BUFFER_SIZE) {
        assert(0 && "Buffer overflow detected proactively!");
        return;
    }
    memcpy(buf_ptr, s, len);
    buf_ptr += len;
    *buf_ptr = '\0'; // 确保字符串始终以 \0 结尾
}

static void gen_space() {
    int num = choose(4); // 0-3
    //每次拼接一个空格
    for (int i = 0; i < num; i++) {
        append(" ", 1);
    }
}

static void gen_num() {
    char num_str[15];
    // 使用 sprintf 生成数字字符串，并获取其长度
    int len = sprintf(num_str, "%uu", (uint32_t)rand() % UINT32_MAX);
    // 直接把字符串和它的长度传递过去，避免了 strlen
    append(num_str, len);
    gen_space();
}

static void gen_rand_op() {
    const char *op[] = {"+", "-", "*", "/", "%", "==", "!=", "<=", ">="};
    size_t num_ops = sizeof(op) / sizeof(op[0]);
    const char *chosen_op = op[choose(num_ops)];
    append(chosen_op, strlen(chosen_op)); // 计算选中字符串的实际长度
    gen_space();
}

static void gen(char c) {
    char str[2] = {c, '\0'};
    append(str, 1);
    gen_space();
}

static void gen_rand_expr(uint32_t depth) {
    if (depth == 0) {
        gen_num();
        return;
    }

    switch (choose(3)) {
        case 0: gen_num(); break;
        case 1: gen('('); gen_rand_expr(depth - 1); gen(')'); break;
        default: gen_rand_expr(depth - 1); gen_rand_op(); gen_rand_expr(depth - 1); break;
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
        // 每次循环开始时，重置指针和缓冲区的第一个字节
        buf_ptr = buf;
        buf[0] = '\0';
        
        gen_rand_expr(MAX_DEPTH);

        sprintf(code_buf, code_format, buf);

        // 以写入方式打开文件
        FILE *fp = fopen("/tmp/.code.c", "w");
        assert(fp != NULL);
        // 将生成的代码写入文件
        fputs(code_buf, fp);
        fclose(fp);

        // 将除零警告转换为错误,检查返回值,出现除0则丢弃
        int ret = system("gcc -Wall -Werror -Wno-parentheses -Wno-unused-variable /tmp/.code.c -o /tmp/.expr");
        if (ret != 0) {
            i--;
            continue;
        }

        // 执行生成的程序并使用管道读取其输出
        fp = popen("/tmp/.expr", "r");
        assert(fp != NULL);

        int result;
        // 注意：这里应该用 %u 来读取无符号数，与 printf 对应
        ret = fscanf(fp, "%u", &result); 
        pclose(fp);

        printf("%u %s\n", result, buf);
    }
    return 0;
}