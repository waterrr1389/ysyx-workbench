#include <am.h>
#include <klib.h>
#include <klib-macros.h>
#include <stdarg.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

int printf(const char *fmt, ...) {
  panic("Not implemented");
}

int vsprintf(char *out, const char *fmt, va_list ap) {
  panic("Not implemented");
}

// 辅助函数：将整数转换为字符串写入 buffer，返回写入的长度
static int _write_int(char *out, int num) {
    char temp[32]; // 足够容纳 64位整数
    int i = 0;
    int len = 0;
    unsigned int u_num;

    // 处理 0 的特殊情况
    if (num == 0) {
        if (out) out[0] = '0';
        return 1;
    }

    // 处理负数 (使用 unsigned 防止 INT_MIN 溢出)
    if (num < 0) {
        if (out) out[len] = '-';
        len++;
        u_num = (unsigned int)(-(num + 1)) + 1; // 安全的绝对值转换
    } else {
        u_num = (unsigned int)num;
    }

    // 倒序生成数字
    while (u_num > 0) {
        temp[i++] = (u_num % 10) + '0';
        u_num /= 10;
    }

    // 将倒序的数字反转写入 out
    for (int j = 0; j < i; j++) {
        if (out) out[len++] = temp[i - 1 - j];
    }
    
    return len;
}

int sprintf(char *out, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);

    char *start = out; // 记录起始位置
    const char *p = fmt;

    while (*p != '\0') {
        if (*p != '%') {
            // 普通字符直接复制
            *out++ = *p++;
            continue;
        }

        // 遇到 %，查看下一个字符
        p++; 
        
        // 如果字符串以 % 结尾（非法格式），直接退出循环
        if (*p == '\0') break;

        switch (*p) {
            case 'd': {
                int val = va_arg(args, int);
                int written = _write_int(out, val);
                out += written;
                break;
            }
            case 's': {
                char *str = va_arg(args, char *);
                if (str == NULL) str = "(null)"; // 标准库通常处理 NULL 的行为
                int len = strlen(str);
                for (int i = 0; i < len; i++) {
                    *out++ = str[i];
                }
                break;
            }
            case '%': {
                // 处理 %%
                *out++ = '%';
                break;
            }
            default:
                // 遇到不支持的说明符，原样打印 (如 %x -> %x)
                *out++ = '%';
                *out++ = *p;
                break;
        }
        p++; // 移动到说明符后的下一个字符
    }

    *out = '\0'; // 必须加上 NULL 结尾
    va_end(args);

    // 返回写入的字符数（不包含结尾的 \0）
    return (int)(out - start);
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  panic("Not implemented");
}

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  panic("Not implemented");
}

#endif
