#!/usr/bin/env bash
# Runs every cpu-test on the current build/Vtop in parallel and prints one line per test.
# Exit status is 0 only if every test hits a good trap.
#   usage: scripts/regress.sh [TEST...]     (default: all tests)
#   env:   ARCH (riscv32e-npc), JOBS (nproc), TIMEOUT seconds per test (60)
set -u

ARCH=${ARCH:-riscv32e-npc}
JOBS=${JOBS:-$(nproc)}
TIMEOUT=${TIMEOUT:-60}
NPC_DIR=$(cd "$(dirname "$0")/.." && pwd)
TESTS_DIR=$(cd "$NPC_DIR/../am-kernels/tests/cpu-tests" && pwd)
VTOP=$NPC_DIR/build/Vtop
LOG_DIR=$NPC_DIR/build/regress
[ -x "$VTOP" ] || { echo "regress: $VTOP missing, run make sim first" >&2; exit 2; }

if [ $# -gt 0 ]; then
  tests=("$@")
else
  mapfile -t tests < <(cd "$TESTS_DIR/tests" && ls *.c | sed 's/\.c$//' | sort)
fi

# Images are built serially by AM; only the simulations run in parallel.
for t in "${tests[@]}"; do
  printf 'NAME = %s\nSRCS = tests/%s.c\ninclude %s/Makefile\n' "$t" "$t" "$AM_HOME" > "$TESTS_DIR/Makefile.regress.$t"
  make -s -C "$TESTS_DIR" -f "Makefile.regress.$t" ARCH="$ARCH" image > /dev/null || { echo "regress: build of $t failed" >&2; rm -f "$TESTS_DIR/Makefile.regress.$t"; exit 2; }
  rm -f "$TESTS_DIR/Makefile.regress.$t"
done

mkdir -p "$LOG_DIR"
run_one() {
  local t=$1 img=$TESTS_DIR/build/$1-$ARCH
  timeout "$TIMEOUT" "$VTOP" -b -e "$img.elf" "$img.bin" > "$LOG_DIR/$t.log" 2>&1
  local rc=$? line
  line=$(grep -a 'npc: result=' "$LOG_DIR/$t.log" | sed 's/\x1b\[[0-9;]*m//g; s/^npc: //')
  [ $rc -eq 124 ] && line="result=timeout"
  if [ $rc -eq 0 ]; then printf '%-16s PASS  %s\n' "$t" "$line"; else printf '%-16s FAIL  %s  (log: %s)\n' "$t" "${line:-rc=$rc}" "$LOG_DIR/$t.log"; fi
  return $rc
}
export -f run_one
export TESTS_DIR ARCH VTOP LOG_DIR TIMEOUT

printf '%s\n' "${tests[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one {}' > "$LOG_DIR/summary" 
rc=$?
sort "$LOG_DIR/summary"
pass=$(grep -c ' PASS ' "$LOG_DIR/summary")
echo "regress: $pass/${#tests[@]} passed ($ARCH)"
[ $rc -eq 0 ]
