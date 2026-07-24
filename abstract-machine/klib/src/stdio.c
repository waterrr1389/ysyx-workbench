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
        u_num = (unsigned int)(-(num + 1)) + 1; // Avoid signed overflow for INT_MIN
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
    enum FormatState {
        FORMAT_TEXT,
        FORMAT_SPECIFIER,
    } state = FORMAT_TEXT;

    char *start = out;
    const char *p = fmt;

    while (*p != '\0') {
        switch (state) {
            case FORMAT_TEXT:
                if (*p == '%') {
                    state = FORMAT_SPECIFIER;
                } else {
                    out = write_char(out, *p);
                }
                break;

            case FORMAT_SPECIFIER:
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
                state = FORMAT_TEXT;
                break;
        }
        p++;
    }

    if (state == FORMAT_SPECIFIER) {
        out = write_char(out, '%');
    }

    *out = '\0'; // append '\0' as the end of string
    return (int)(out - start);
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  panic("Not implemented");
}

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  panic("Not implemented");
}

#endif
