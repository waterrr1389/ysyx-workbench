#pragma once

#include <dlfcn.h>
#include "base/utils.h"
#include "base/debug.h"
#include "base/common.h"
#include "sim/pmem.h"


enum { DIFFTEST_TO_DUT, DIFFTEST_TO_REF };

void init_difftest(const char* ref_so_file, long img_size);