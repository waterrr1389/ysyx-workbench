#pragma once

#include "base/common.h"

#define Assert(cond, format, ...) \
  do { \
    if (!(cond)) { \
      fflush(stdout); \
      fprintf(stderr, format "\n", ## __VA_ARGS__); \
      assert(cond); \
    } \
  } while (0)
