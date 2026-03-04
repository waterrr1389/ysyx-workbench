#!/usr/bin/env bash
set -euo pipefail

RUNS=5
INTERP_BIN="build/riscv32-nemu-interpreter"
JIT_BIN="build/riscv32-nemu-jit"
MIN_TIME_US=100
TIMEOUT_SEC=3

usage() {
  cat <<'USAGE'
Usage:
  scripts/bench-jit-vs-interpreter.sh [options] [img1 img2 ...]

Options:
  -n, --runs N           Number of runs per image (default: 5)
  -m, --min-us N         Minimum host time(us) to include sample (default: 100)
  -t, --timeout S        Per-run timeout in seconds (default: 3)
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
    -m|--min-us)
      MIN_TIME_US="$2"
      shift 2
      ;;
    -t|--timeout)
      TIMEOUT_SEC="$2"
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

if ! [[ "$MIN_TIME_US" =~ ^[0-9]+$ ]]; then
  echo "Invalid --min-us: $MIN_TIME_US" >&2
  exit 1
fi

if ! [[ "$TIMEOUT_SEC" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT_SEC" -le 0 ]]; then
  echo "Invalid --timeout: $TIMEOUT_SEC" >&2
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

extract_guest_inst() {
  local output="$1"
  echo "$output" | sed -n 's/.*total guest instructions = \([0-9,]\+\).*/\1/p' | head -n 1 | tr -d ','
}

extract_host_us() {
  local output="$1"
  echo "$output" | sed -n 's/.*host time spent = \([0-9,]\+\) us.*/\1/p' | head -n 1 | tr -d ','
}

sample_freq() {
  local exe="$1"
  local img="$2"

  local out
  out=$(timeout "$TIMEOUT_SEC" "$exe" --batch --log=/dev/null "$img" 2>&1 || true)

  local freq
  freq=$(extract_freq "$out")
  if [[ -n "$freq" ]]; then
    echo "$freq"
    return 0
  fi

  local host_us
  host_us=$(extract_host_us "$out")
  local guest_inst
  guest_inst=$(extract_guest_inst "$out")

  if [[ -z "$host_us" || -z "$guest_inst" ]]; then
    echo "Failed to parse timing or instructions." >&2
    echo "Executable: $exe" >&2
    echo "Image: $img" >&2
    echo "Last output:" >&2
    echo "$out" | tail -n 20 >&2
    return 1
  fi

  if [[ "$host_us" -eq 0 ]]; then
    return 2
  fi

  if [[ "$host_us" -lt "$MIN_TIME_US" ]]; then
    return 2
  fi

  awk -v gi="$guest_inst" -v us="$host_us" 'BEGIN { printf "%.0f", gi * 1000000.0 / us }'
}

avg_freq() {
  local exe="$1"
  local img="$2"
  local sum=0
  local cnt=0
  local attempts=0
  local max_attempts=$((RUNS * 50))

  while [[ "$cnt" -lt "$RUNS" && "$attempts" -lt "$max_attempts" ]]; do
    attempts=$((attempts + 1))

    local freq
    freq=$(sample_freq "$exe" "$img")
    code=$?
    if [[ "$code" -eq 2 ]]; then
      continue
    fi
    if [[ "$code" -ne 0 ]]; then
      return 1
    fi

    if [[ -z "$freq" ]]; then
      continue
    fi

    sum=$((sum + freq))
    cnt=$((cnt + 1))
  done

  if [[ "$cnt" -eq 0 ]]; then
    echo "No valid samples for $img (host time too short)." >&2
    echo "Tip: use a heavier image or reduce --min-us (current: $MIN_TIME_US)." >&2
    return 1
  fi

  if [[ "$cnt" -lt "$RUNS" ]]; then
    echo "Warning: only $cnt/$RUNS valid samples for $(basename "$img")" >&2
  fi

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

  if ! interp_avg=$(avg_freq "$INTERP_BIN" "$img"); then
    echo "Skip (interpreter too short or parse failed): $(basename "$img")" >&2
    continue
  fi

  if ! jit_avg=$(avg_freq "$JIT_BIN" "$img"); then
    echo "Skip (jit too short or parse failed): $(basename "$img")" >&2
    continue
  fi

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
