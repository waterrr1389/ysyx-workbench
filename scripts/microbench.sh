#!/usr/bin/env bash
# Runs am-kernels microbench on ysyxSoC with performance counters.
# Usage: microbench.sh SIM AM_KERNELS [test|train|ref]
set -e
sim=$1; dir=$2/benchmarks/microbench; size=${3:-train}
make -s -C "$dir" ARCH=riscv32e-ysyxsoc image > /dev/null
img=$(mktemp --suffix=.bin)
cp "$dir/build/microbench-riscv32e-ysyxsoc.bin" "$img"
python3 "$AM_HOME/tools/insert-arg.py" "$img" 64 the_insert-arg_rule_in_Makefile_will_insert_mainargs_here "$size" > /dev/null
log=$(mktemp)
timeout 72000 "$sim" --flash "$img" --perf --max-cycles 400000000000 2>&1 | tee "$log"
rm -f "$img"
grep -aq "MicroBench PASS" "$log" && grep -aq "HIT GOOD TRAP" "$log"
