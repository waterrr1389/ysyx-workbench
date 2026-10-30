#!/usr/bin/env bash
# Runs the handout's mem-test over PSRAM and SDRAM. Usage: test-mem.sh SIM AM_KERNELS [KiB]
# Without KiB the whole of each memory is tested (PSRAM 4 MiB, SDRAM 128 MiB; this takes hours).
set -e
sim=$1; dir=$2/tests/mem-test; kib=$3
make -s -C "$dir" ARCH=riscv32e-ysyxsoc image > /dev/null
tmp=$(mktemp -d)
for mem in psram sdram; do
  img=$tmp/$mem.bin
  cp "$dir/build/mem-test-riscv32e-ysyxsoc.bin" "$img"
  python3 "$AM_HOME/tools/insert-arg.py" "$img" 64 the_insert-arg_rule_in_Makefile_will_insert_mainargs_here \
    "$mem${kib:+ $kib}" > /dev/null
  echo "== mem-test $mem${kib:+ ($kib KiB)}"
  timeout 36000 "$sim" --flash "$img" --max-cycles 200000000000 2>&1 | tee "$tmp/$mem.log" | grep -av '^$'
  grep -aq "mem-test PASS" "$tmp/$mem.log" && grep -aq "HIT GOOD TRAP" "$tmp/$mem.log"
done
rm -rf "$tmp"
echo "mem-test: PSRAM and SDRAM passed"
