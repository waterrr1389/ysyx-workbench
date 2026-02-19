#!/usr/bin/env bash
set -euo pipefail

RUNS=5
INTERP_BIN="build/riscv32-nemu-interpreter"
JIT_BIN="build/riscv32-nemu-jit"

usage() {
  cat <<'USAGE'
Usage:
  scripts/bench-jit-vs-interpreter.sh [options] [img1 img2 ...]

Options:
  -n, --runs N           Number of runs per image (default: 5)
  -i, --interp PATH      Interpreter binary path (default: build/riscv32-nemu-interpreter)
  -j, --jit PATH         JIT binary path (default: build/riscv32-nemu-jit)
  -h, --help             Show this help

If no images are provided, the script auto-discovers from:
  ../am-kernels/tests/cpu-tests/build/*-riscv32-nemu.bin
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--runs)
      RUNS="$2"
      shift 2
      ;;
    -i|--interp)
      INTERP_BIN="$2"
      shift 2
      ;;
    -j|--jit)
      JIT_BIN="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [[ "$RUNS" -le 0 ]]; then
  echo "Invalid runs: $RUNS" >&2
  exit 1
fi

if [[ ! -x "$INTERP_BIN" ]]; then
  echo "Interpreter binary not found or not executable: $INTERP_BIN" >&2
  exit 1
fi

if [[ ! -x "$JIT_BIN" ]]; then
  echo "JIT binary not found or not executable: $JIT_BIN" >&2
  exit 1
fi

declare -a IMGS=()
if [[ $# -gt 0 ]]; then
  while [[ $# -gt 0 ]]; do
    IMGS+=("$1")
    shift
  done
else
  while IFS= read -r line; do
    IMGS+=("$line")
  done < <(find ../am-kernels/tests/cpu-tests/build -maxdepth 1 -type f -name "*-riscv32-nemu.bin" | sort)
fi

if [[ ${#IMGS[@]} -eq 0 ]]; then
  echo "No images found. Pass image paths explicitly." >&2
  exit 1
fi

extract_freq() {
  local output="$1"
  echo "$output" | sed -n 's/.*simulation frequency = \([0-9,]\+\) inst\/s.*/\1/p' | head -n 1 | tr -d ','
}

avg_freq() {
  local exe="$1"
  local img="$2"
  local sum=0
  local cnt=0

  for ((k=1; k<=RUNS; k++)); do
    local out
    out=$("$exe" --batch --log=/dev/null "$img" 2>&1 || true)

    local freq
    freq=$(extract_freq "$out")

    if [[ -z "$freq" ]]; then
      echo "Failed to parse simulation frequency." >&2
      echo "Executable: $exe" >&2
      echo "Image: $img" >&2
      echo "Last output:" >&2
      echo "$out" | tail -n 20 >&2
      return 1
    fi

    sum=$((sum + freq))
    cnt=$((cnt + 1))
  done

  awk -v s="$sum" -v c="$cnt" 'BEGIN { printf "%.2f", s / c }'
}

printf "%-30s %16s %16s %12s\n" "Image" "Interp(inst/s)" "JIT(inst/s)" "Speedup"
printf "%-30s %16s %16s %12s\n" "------------------------------" "----------------" "----------------" "------------"

all_interp=0
all_jit=0
img_cnt=0

for img in "${IMGS[@]}"; do
  if [[ ! -f "$img" ]]; then
    echo "Skip (not found): $img" >&2
    continue
  fi

  interp_avg=$(avg_freq "$INTERP_BIN" "$img")
  jit_avg=$(avg_freq "$JIT_BIN" "$img")

  speedup=$(awk -v i="$interp_avg" -v j="$jit_avg" 'BEGIN { if (i == 0) print "nan"; else printf "%.3fx", j / i }')

  printf "%-30s %16s %16s %12s\n" "$(basename "$img")" "$interp_avg" "$jit_avg" "$speedup"

  all_interp=$(awk -v a="$all_interp" -v b="$interp_avg" 'BEGIN { printf "%.2f", a + b }')
  all_jit=$(awk -v a="$all_jit" -v b="$jit_avg" 'BEGIN { printf "%.2f", a + b }')
  img_cnt=$((img_cnt + 1))
done

if [[ "$img_cnt" -eq 0 ]]; then
  echo "No valid images were benchmarked." >&2
  exit 1
fi

global_interp=$(awk -v s="$all_interp" -v c="$img_cnt" 'BEGIN { printf "%.2f", s / c }')
global_jit=$(awk -v s="$all_jit" -v c="$img_cnt" 'BEGIN { printf "%.2f", s / c }')
global_speedup=$(awk -v i="$global_interp" -v j="$global_jit" 'BEGIN { if (i == 0) print "nan"; else printf "%.3fx", j / i }')

echo
echo "Summary (${img_cnt} images, ${RUNS} runs each):"
echo "  Interpreter avg: ${global_interp} inst/s"
echo "  JIT avg:         ${global_jit} inst/s"
echo "  Speedup:         ${global_speedup}"
