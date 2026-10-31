#!/usr/bin/env bash
# Runs all am-kernels cpu-tests on ysyxSoC with DiffTest, in parallel, and fails if any test other
# than `wrong` fails.
# Usage: test-cpu.sh SIM CPU_TESTS_DIR
sim=$1
dir=$2
jobs=$(nproc)
names=$(cd "$dir/tests" && ls *.c | sed 's/\.c$//')

build() {
  local mk="$dir/Makefile.$1"
  printf "NAME = %s\nSRCS = tests/%s.c\ninclude \${AM_HOME}/Makefile\n" "$1" "$1" > "$mk"
  make -s -C "$dir" -f "Makefile.$1" ARCH=riscv32e-ysyxsoc image > /dev/null 2>&1
  local rc=$?
  rm -f "$mk"
  return $rc
}

run() {
  local out
  out=$(timeout 1800 "$sim" --flash "$dir/build/$1-riscv32e-ysyxsoc.bin" --max-cycles 500000000 --difftest 2>&1)
  if echo "$out" | grep -aq "HIT GOOD TRAP"; then
    printf "[%14s] PASS\n" "$1"
  else
    printf "[%14s] ***FAIL*** %s\n" "$1" "$(echo "$out" | grep -a '\[sim\]\|difftest' | head -1)"
  fi
}
export -f build run
export sim dir

# The first build also builds the AM library the others share.
first=$(echo "$names" | head -1)
build "$first" || { echo "cpu-tests: build of $first failed"; exit 1; }
echo "$names" | tail -n +2 | xargs -P "$jobs" -I{} bash -c 'build {} || echo "build of {} failed"'

results=$(echo "$names" | xargs -P "$jobs" -I{} bash -c 'run {}' | sort)
echo "$results"
total=$(echo "$results" | wc -l)
failed=$(echo "$results" | grep FAIL | grep -v '\[ *wrong\]')
if [ -n "$failed" ] || [ "$total" -lt 2 ]; then
  echo "cpu-tests: FAILED"; exit 1
fi
echo "cpu-tests: all $((total - 1)) tests passed (\`wrong\` is expected to fail)"
