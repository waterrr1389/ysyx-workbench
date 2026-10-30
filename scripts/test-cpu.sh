#!/usr/bin/env bash
# Runs all am-kernels cpu-tests on ysyxSoC and fails if any test other than `wrong` fails.
set -o pipefail
log=$(mktemp)
make -C "$1" ARCH=riscv32e-ysyxsoc run 2>&1 | tee "$log" | grep -aE '^\[ *[a-z0-9-]+\] |\[sim\]|difftest'
results=$(grep -aE '^\[ *[a-z0-9-]+\] .*(PASS|FAIL)' "$log")
rm -f "$log"
total=$(echo "$results" | wc -l)
failed=$(echo "$results" | grep FAIL | grep -v '\[ *wrong\]')
if [ -n "$failed" ] || [ "$total" -lt 2 ]; then
  echo "cpu-tests: FAILED"; echo "$failed"; exit 1
fi
echo "cpu-tests: all $((total - 1)) tests passed (\`wrong\` is expected to fail)"
