#!/usr/bin/env bash
# Runs the fence.i self-modifying-code test with DiffTest; passes when the test reports PASS.
# Usage: test-fencei.sh SIM [--expect-fail]
sim=$1
dir=$(dirname "$0")/../tests/fencei
make -s -C "$dir" ARCH=riscv32e-ysyxsoc image > /dev/null || exit 1
dt=--difftest; [ "$2" = --expect-fail ] && dt=
out=$(timeout 600 "$sim" $dt --flash "$dir/build/fencei-riscv32e-ysyxsoc.bin" --max-cycles 50000000 2>&1)
echo "$out" | grep -a "patch_next\|call_func\|fence.i test\|\[sim\]"
if [ "$2" = --expect-fail ]; then
  echo "$out" | grep -aq "fence.i test FAIL" && echo "fence.i: fails as expected"
else
  echo "$out" | grep -aq "fence.i test PASS"
fi
