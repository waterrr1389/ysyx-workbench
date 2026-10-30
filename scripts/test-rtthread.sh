#!/usr/bin/env bash
# Boots RT-Thread on ysyxSoC and types a shell command over the UART RX pin once the built-in
# commands have run, then checks the command's output. Usage: test-rtthread.sh SIM RT_THREAD_BSP
set -e
sim=$1; bsp=$2
[ -f "$bsp/rtconfig.h" ] || make -C "$bsp" init > /dev/null
make -s -C "$bsp" ARCH=riscv32e-ysyxsoc > /dev/null 2>&1
log=$(mktemp)
timeout 3600 "$sim" --flash "$bsp/build/rtthread-riscv32e-ysyxsoc.bin" --max-cycles 1500000000 \
  --uart-input 'am_hello\n' --uart-after 'msh />utest_list' \
  --uart-exit 'Hello, AbstractMachine!' > "$log" 2>&1 || true
# Show the typed command and its result.
grep -a -A3 'msh />am_hello' "$log"
tail -n1 "$log"
if grep -a -A1 'msh />am_hello' "$log" | grep -aq 'Hello, AbstractMachine!'; then
  echo "rt-thread: shell command typed over UART ran"; rm -f "$log"
else
  echo "rt-thread: FAILED (log in $log)"; exit 1
fi
