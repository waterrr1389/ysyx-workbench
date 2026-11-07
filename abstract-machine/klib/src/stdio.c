#include <am.h>
#include <klib.h>
#include <klib-macros.h>
#include <stdarg.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

static char* write_char(char* dst, char ch) {
    if (dst) *dst = ch;
    return dst + 1;
}

// Formats num in decimal into buf, without a terminator, and returns its length.
// buf must hold 11 characters: the sign and the 10 digits of INT_MIN.
static int format_int(char *buf, int num) {
    char digits[10];
    int n = 0, len = 0;
    unsigned int u_num;

    if (num < 0) {
        buf[len++] = '-';
        u_num = (unsigned int)(-(num + 1)) + 1; // Avoid signed overflow for INT_MIN
    } else {
        u_num = (unsigned int)num;
    }

    do {
        digits[n++] = (u_num % 10) + '0';
        u_num /= 10;
    } while (u_num > 0);

    while (n > 0) buf[len++] = digits[--n];
    return len;
}

// Writes s[0..len) right-aligned in a field of at least width characters.
// Zero padding goes between the sign and the digits, as in "-0042".
static char* write_field(char *out, const char *s, int len, int width, bool zero_pad) {
    int pad = width > len ? width - len : 0;

    if (zero_pad && len > 0 && s[0] == '-') {
        out = write_char(out, '-');
        s++;
        len--;
    }
    for (; pad > 0; pad--) out = write_char(out, zero_pad ? '0' : ' ');
    for (int i = 0; i < len; i++) out = write_char(out, s[i]);
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

// Supports %d, %c, %s and %%, each with an optional '0' flag and a field width,
// as in "%02d" or "%8s". The '0' flag pads only %d; strings and characters pad
// with spaces. An unsupported specification is copied to the output unchanged.
int vsprintf(char *out, const char *fmt, va_list args) {
    char *start = out;
    const char *p = fmt;

    while (*p != '\0') {
        if (*p != '%') {
            out = write_char(out, *p++);
            continue;
        }

        const char *spec = p++;
        bool zero_pad = false;
        int width = 0;

        while (*p == '0') {
            zero_pad = true;
            p++;
        }
        while (*p >= '0' && *p <= '9') {
            width = width * 10 + (*p - '0');
            p++;
        }

        switch (*p) {
            case 'd': {
                char buf[11];
                int len = format_int(buf, va_arg(args, int));
                out = write_field(out, buf, len, width, zero_pad);
                break;
            }
            case 'c': {
                char ch = (char)va_arg(args, int);
                out = write_field(out, &ch, 1, width, false);
                break;
            }
            case 's': {
                const char *str = va_arg(args, const char *);
                if (!str) str = "(null)";
                out = write_field(out, str, (int)strlen(str), width, false);
                break;
            }
            case '%':
                out = write_char(out, '%');
                break;
            default:
                // Includes a '%' at the end of fmt, where *p is the terminator.
                for (const char *q = spec; q <= p && *q != '\0'; q++) {
                    out = write_char(out, *q);
                }
                break;
        }
        if (*p != '\0') p++;
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
