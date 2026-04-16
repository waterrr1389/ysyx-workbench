#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int pmem_read(int raddr);
void pmem_write(int waddr, int wdata, char wmask);
void npc_trap(void);

#ifdef __cplusplus
}
#endif
