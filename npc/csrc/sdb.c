#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <readline/history.h>
#include <readline/readline.h>
#include "sim/sdb.h"
#include "sim/sim_main.h"

#define ARRLEN(arr) (int)(sizeof(arr) / sizeof(arr[0]))
#define NR_CMD ARRLEN(cmd_table)

static int cmd_c(char* args);
static int cmd_q(char* args);
static int cmd_help(char* args);
static int cmd_info(char* args);
static int cmd_si(char* args);

const char *regs[] = {"$0", "ra", "sp",	 "gp",	"tp", "t0", "t1", "t2",
					  "s0", "s1", "a0",	 "a1",	"a2", "a3", "a4", "a5",
					  "a6", "a7", "s2",	 "s3",	"s4", "s5", "s6", "s7",
					  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"};

static char *rl_gets() {
	static char *line_read = NULL;

	if (line_read) {
		free(line_read);
		line_read = NULL;
	}

	line_read = readline("(npc) ");

	if (line_read && *line_read) {
		add_history(line_read);
	}

	return line_read;
}

static struct {
	const char *name;
	const char *description;
	int (*handler)(char *);
} cmd_table[] = {
	{"help", "Display information about all supported commands", cmd_help},
	{"q", "Exit NEMU", cmd_q},
	{"c", "Continue the execution of the program", cmd_c},
	{"si", "Execute N instructions then pause (default N=1)", cmd_si},
	{"info", "Print register status", cmd_info}
};

static int cmd_q(char* args) {
  return -1;
}

static int cmd_c(char* args) {
  while (sim) {
    step_one_cycle();
  }
  return 0;
}

static int cmd_help(char *args) {
	/* extract the first argument */
	char *arg = strtok(NULL, " ");
	int i;

	if (arg == NULL) {
		/* no argument given */
		for (i = 0; i < NR_CMD; i++) {
			printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
		}
	} else {
		for (i = 0; i < NR_CMD; i++) {
			if (strcmp(arg, cmd_table[i].name) == 0) {
				printf("%s - %s\n", cmd_table[i].name,
					   cmd_table[i].description);
				return 0;
			}
		}
		printf("Unknown command '%s'\n", arg);
	}
	return 0;
}

static int cmd_si(char *args) {
	int n;
	if (args == NULL) {
		n = 1;
	} else {
		sscanf(args, "%d", &n);
	}
  for (int i = 0; i < n; i++) {
	  step_one_cycle();
  }

	return 0;
}

static int cmd_info(char* args) {
	for (int i = 0; i < 32; i++) {
		printf("%s: %08x\n", regs[i], read_gpr(i));
	}
	return 0;
}

void sdb_mainloop(void) {
	// see parse_args in monitor/monitor.c
	// In normal case, the value of is_batch_mode is false
	// if (is_batch_mode) {
	// 	cmd_c(NULL);
	// 	return;
	// }

  while(sim) {
  	for (char *str; (str = rl_gets()) != NULL;) {
  		char *str_end = str + strlen(str);

  		/* extract the first token as the command */
  		char *cmd = strtok(str, " ");
  		if (cmd == NULL) {
  			continue;
  		}

  		/* treat the remaining string as the arguments,
  		 * which may need further parsing
  		 */
  		char *args = cmd + strlen(cmd) + 1;
  		if (args >= str_end) {
  			args = NULL;
  		}

  		int i;
  		for (i = 0; i < NR_CMD; i++) {
  			if (strcmp(cmd, cmd_table[i].name) == 0) {
  				// 正常情况下应该返回0,如果返回-1则会退出
  				if (cmd_table[i].handler(args) < 0) {
  					return;
  				}
  				break;
  			}
  		}

  		if (i == NR_CMD) {
  			printf("Unknown command '%s'\n", cmd);
  		}
  	}
  }
}
