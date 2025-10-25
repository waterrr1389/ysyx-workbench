#include <klib.h>
#include <klib-macros.h>
#include <stdint.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

size_t strlen(const char *s) {
  char* pos = (char*)s;
  while(*pos != '\0') {
    pos++;
  }
  return pos - s;
}

char *strcpy(char *dst, const char *src) {
  char* p1 = (char*) src;
  char* p2 = dst;
  while (*p1 != '\0') {
    *p2++ = *p1++;
  }
  *p2 = '\0';
  return dst;
}

char *strncpy(char *dst, const char *src, size_t n) {
  char* p1 = (char*) src;
  char* p2 = dst;
  size_t i;
  for (i = 0; i < n && *p1 != '\0'; i++) {
    *p2++ = *p1++;
  }
  /*
    If the array pointed to by s2 is a string that is shorter than n
    bytes, NUL characters shall be appended to the copy in the array
    pointed to by s1, until n bytes in all are written.
  */
  for (; i < n; i++) {
    *p2++ = '\0';
  }

  return dst;
}

char *strcat(char *dst, const char *src) {
    char* p_dst_end = dst;
    // 1. 找到 dst 的结尾
    while (*p_dst_end != '\0') {
        p_dst_end++;
    }

    // 2. 从 dst 的结尾开始复制 src
    const char* p_src = src; // (const char* p1 = src; 也可以)
    while (*p_src != '\0') {
        *p_dst_end++ = *p_src++;
    }

    // 3. 添加新的结尾符
    *p_dst_end = '\0';
    return dst;
}

int strcmp(const char *s1, const char *s2) {
    size_t index = 0;
    while (s1[index] != '\0' && s1[index] == s2[index]) {
        index++;
    }
    // 循环结束后，s1[index] 和 s2[index] 是第一个不同的字符，或者是 '\0'
    // 使用 unsigned char 来防止负数问题
    return *(s1 + index) - *(s2 + index);
}

int strncmp(const char *s1, const char *s2, size_t n) {
    if (n == 0) return 0;

    for (size_t i = 0; i < n; i++) {
        // 如果字符不同，或者到达 s1 的末尾
        if (s1[i] != s2[i] || s1[i] == '\0') {
            return *(unsigned char*)(s1 + i) - *(unsigned char*)(s2 + i);
        }
    }
    // 如果循环 n 次都相等
    return 0;
}

void* memset(void *s, int c, size_t n) {
  for (size_t i = 0; i < n; i++) {
    *((char*)s + i) = (char)c;
  }
  return s;
}

void* memmove(void *dst, const void *src, size_t n) {
    // 将 void* 转换为 char*，以便进行字节级别的指针运算
    char *p_dst = (char *)dst;
    const char *p_src = (const char *)src;

    // 1. 如果没有字节要复制，或者源和目标相同，则什么都不做
    if (n == 0 || p_dst == p_src) {
        return dst;
    }

    // 2. 检查是否有“破坏性重叠”
    // 这种情况发生在：
    //    a) 目标指针 p_dst 在源指针 p_src *之后*
    //    b) 并且源块的末尾 (p_src + n) 超过了目标块的开头 (p_dst)
    // [src_start...|...dst_start...|...src_end...]
    if (p_dst > p_src && p_src + n > p_dst) {
        // 3a. 存在破坏性重叠：必须从后向前复制
        // 将指针移动到源块和目标块的末尾
        p_src = p_src + n;
        p_dst = p_dst + n;

        // 从后向前逐字节复制
        while (n > 0) {
            n--;
            p_dst--;
            p_src--;
            *p_dst = *p_src;
        }
    } else {
        // 3b. 安全情况：从前向后复制
        // 这包括：
        //    a) p_dst <= p_src (目标在源的前面或相同，向前复制是安全的)
        //    b) p_dst > p_src 但 p_src + n <= p_dst (目标在源的后面，但没有重叠)
        for (size_t i = 0; i < n; i++) {
            p_dst[i] = p_src[i];
        }
    }
    // 4. 按标准返回目标指针
    return dst;
}

void* memcpy(void *out, const void *in, size_t n) {
  char* psrc = (char*)in;
  char* pdst = (char*)out;
  for (size_t i = 0; i < n; i++) {
    *(pdst + i) = *(psrc + i);
  }
  return out;
}

int memcmp(const void *s1, const void *s2, size_t n) {
  if (n == 0) return 0;
  char* c1 = (char*)s1;
  char* c2 = (char*)s2;
  int result = 0;
  for (size_t index = 0; index < n; index++) {
    result = *(unsigned char*)(c1 + index) - *(unsigned char*)(c2 + index);
    if (result) {
      return result;
    }
  }
  return result;
}

#endif
