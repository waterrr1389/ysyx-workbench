#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int pmem_read(int raddr);
void pmem_write(int waddr, int wdata, char wmask);
void npc_trap(void);
void npc_abort_at(const char* reason);

#ifdef __cplusplus
}
#endif
