#include <am.h>
#include <klib.h>
#include <klib-macros.h>
#include <stdarg.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

static char* write_char(char* dst, char ch) {
    if (dst) *dst = ch;
    return dst + 1;
}

static char* write_int(char *out, int num) {
    char temp[32];
    int i = 0;
    unsigned int u_num;

    if (num == 0) return write_char(out, '0');

    if (num < 0) {
        out = write_char(out, '-');
        u_num = (unsigned int)(-(num + 1)) + 1;
    } else {
        u_num = (unsigned int)num;
    }

    while (u_num > 0) {
        temp[i++] = (u_num % 10) + '0';
        u_num /= 10;
    }

    while (i > 0) {
        out = write_char(out, temp[--i]);
    }
    return out;
}

int sprintf(char *out, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    
    int len = vsprintf(out, fmt, args); 
    
    va_end(args);
    return len;
}

int printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char temp[512] = {0};
    int size = vsprintf(temp, fmt, args);

    for (int i = 0; i < size; i++) {
        putch(temp[i]);
    }

    va_end(args);

    return size;
}

int vsprintf(char *out, const char *fmt, va_list args) {
    char *start = out;
    const char *p = fmt;

    while (*p != '\0') {
        if (*p != '%') {
            out = write_char(out, *p);
            p++;
            continue;
        }

        p++; 
        if (*p == '\0') break;

        switch (*p) {
            case 'd':
                out = write_int(out, va_arg(args, int));
                break;
            case 'c':
                out = write_char(out, (char)va_arg(args, int));
                break;
            case 's': {
                char *str = va_arg(args, char *);
                if (!str) str = "(null)";
                for (int i = 0; str[i] != '\0'; i++) {
                    out = write_char(out, str[i]);
                }
                break;
            }
            case '%':
                out = write_char(out, '%');
                break;
            default:
                out = write_char(out, '%');
                out = write_char(out, *p);
                break;
        }
        p++;
    }

    if (out) *out = '\0';
    return (int)(out - start);
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  panic("Not implemented");
}

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  panic("Not implemented");
}

#endif
