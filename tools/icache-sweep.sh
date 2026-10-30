#!/usr/bin/env bash
# Runs cachesim over icache shapes of 64-256 bytes on one fetch trace, in parallel.
# Usage: icache-sweep.sh TRACE   (output: block sets ways policy pad accesses misses)
set -e
trace=$1
bin=$(mktemp)
g++ -O2 -o "$bin" "$(dirname "$0")/cachesim.cpp"
for b in 4 8 16 32; do for total in 64 128 256; do for w in 1 2 4; do
  s=$((total / b / w)); [ $s -ge 1 ] && echo "$b $s $w"
done; done; done | xargs -P "$(nproc)" -L 1 sh -c "\"$bin\" \"$trace\" \$0 \$1 \$2 lru"
rm -f "$bin"
