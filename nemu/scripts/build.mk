.DEFAULT_GOAL = app

# Add necessary options if the target is a shared library
ifeq ($(SHARE),1)
SO = -so
CFLAGS  += -fPIC -fvisibility=hidden
LDFLAGS += -shared -fPIC
endif

WORK_DIR  = $(shell pwd)
BUILD_DIR = $(WORK_DIR)/build

INC_PATH := $(WORK_DIR)/include $(INC_PATH)
OBJ_DIR  = $(BUILD_DIR)/obj-$(NAME)$(SO)
BINARY   = $(BUILD_DIR)/$(NAME)$(SO)

# Compilation flags
ifeq ($(CC),clang)
CXX := clang++
else
CXX := g++
endif
LD := $(CXX)
INCLUDES = $(addprefix -I, $(INC_PATH))
CFLAGS  := -O2 -MMD -Wall -Werror $(INCLUDES) $(CFLAGS)
LDFLAGS := -O2 $(LDFLAGS)

OBJS = $(SRCS:%.c=$(OBJ_DIR)/%.o) $(CXXSRC:%.cc=$(OBJ_DIR)/%.o)

# Compile commands, shared by the rules below and by compile_commands.json.
# Must use `=` so that `$@` and `$<` expand inside each rule, not here.
C_COMPILE   = $(CC) $(CFLAGS) -c -o $@ $<
CXX_COMPILE = $(CXX) $(CFLAGS) $(CXXFLAGS) -c -o $@ $<

# Escape a string for JSON: `\` first, then `"`
json_esc = $(subst ",\",$(subst \,\\,$(1)))

# Write a compile_commands.json entry next to the object as `$@.json`.
# $(file) bypasses the shell, which would otherwise re-parse the quotes in CFLAGS.
# $(file) expands before the recipe runs, so the directory is created with $(shell).
define record_compile
$(shell mkdir -p $(dir $@))$(file >$@.json,{"directory":"$(WORK_DIR)","file":"$(abspath $<)","command":"$(call json_esc,$(1))"})
endef

# Compilation patterns
$(OBJ_DIR)/%.o: %.c
	@echo + CC $<
	@mkdir -p $(dir $@)
	@$(C_COMPILE)
	@$(CC) $(CFLAGS) -E -o $@.i $<
	$(call call_fixdep, $(@:.o=.d), $@)
	$(call record_compile,$(C_COMPILE))

$(OBJ_DIR)/%.o: %.cc
	@echo + CXX $<
	@mkdir -p $(dir $@)
	@$(CXX_COMPILE)
	$(call call_fixdep, $(@:.o=.d), $@)
	$(call record_compile,$(CXX_COMPILE))

# clangd: per-object entries -> build/compile_commands.json
# clangd finds it by searching `build/` under each parent directory of a source file.
# Objects compiled before this rule existed have no entry; `make clean` once to fill them in.
COMPILE_DB = $(BUILD_DIR)/compile_commands.json
$(COMPILE_DB): $(OBJS)
	@for f in $(addsuffix .json,$(OBJS)); do [ -f $$f ] && cat $$f; done | { echo '['; paste -sd, -; echo ']'; } > $@

# Depencies
-include $(OBJS:.o=.d)

# Some convenient rules

.PHONY: app clean

app: $(BINARY)

$(BINARY):: $(OBJS) $(ARCHIVES) $(COMPILE_DB)
	@echo + LD $@
	@$(LD) -o $@ $(OBJS) $(LDFLAGS) $(ARCHIVES) $(LIBS)

clean:
	-rm -rf $(BUILD_DIR)
