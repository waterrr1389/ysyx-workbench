#pragma once

#ifndef NPC_ITRACE
#define NPC_ITRACE 0
#endif

#ifndef NPC_FTRACE
#define NPC_FTRACE 0
#endif

#ifndef NPC_MTRACE
#define NPC_MTRACE 0
#endif

#define NPC_NEED_INST_TRACE (NPC_ITRACE || NPC_FTRACE)
