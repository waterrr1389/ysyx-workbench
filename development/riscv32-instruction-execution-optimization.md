# RV32 Instruction Execution Optimization

Status: Completed

## Context

The RV32 interpreter currently performs instruction selection through 56
sequential `INSTPAT` entries in `nemu/src/isa/riscv32/inst.c`. The file also
owns operand decoding, instruction execution, CSR access, control-flow updates,
and several debugging hooks.

The compiler may fold the constant pattern strings into masks and keys, but the
resulting instruction-selection path can still contain many unrelated
comparisons. Common instructions are not consistently near the beginning of
the chain. The actual performance cost must be measured before choosing a
replacement.

This work is intended to improve the RV32 interpreter without turning NEMU into
a JIT or basic-block translator.

## Goals

- Improve RV32 instruction throughput.
- Reduce unnecessary instruction-pattern comparisons.
- Make RV32 decode and execution easier to inspect and extend.
- Preserve instruction-level visibility and debugging behavior.
- Preserve Spike DiffTest compatibility.
- Keep each optimization independently measurable and reversible.

## Non-goals

- Optimizing `vaddr`, `paddr`, RAM, MMIO, or address translation.
- Migrating or validating other ISAs.
- Implementing JIT, dynamic binary translation, or basic-block execution.
- Migrating the shared CPU execution loop unless later measurements show a
  concrete need.
- Introducing general-purpose containers or dynamic allocation into the
  instruction hot path.

## Affected modules

Primary:

- `nemu/src/isa/riscv32/inst.cc`
- RV32 ISA-local build declarations required for a C++ source file

Conditional:

- RV32-local profiling support
- `nemu/src/cpu/cpu-exec.c`, only if a later accepted design requires a minimal
  interface for profiling or cache lifecycle

The virtual and physical memory interfaces remain unchanged.

## Confirmed decisions

- Optimize only the RV32 instruction path.
- Do not optimize the memory path as part of this work.
- Use MicroBench `train` for development comparisons.
- Use MicroBench `ref` only for final confirmation.
- Run a benchmark once by default; repeat only when the result is close,
  inconsistent, or otherwise suspicious.
- Convert the RV32 instruction implementation to C++ as a behavior-preserving
  step before mixing in structural optimizations.
- Prefer `.cc`, which is already supported by the NEMU build rules.
- Evaluate hierarchical opcode decoding before considering a decoded
  instruction cache.
- Do not use `std::unordered_map` for instruction caching.
- Keep CPU Tests serialized with `-j 1`.

## Proposals requiring measurement

- Replace the sequential pattern chain with primary opcode groups followed by
  `funct3`, `funct7`, or immediate-field selection.
- Keep decode and execution in the same branch initially so the compiler can
  inline short instruction semantics.
- Extract small inline primitives for immediate decoding, register access, CSR
  access, and branch target calculation when this reduces duplication.
- Add a fixed-size direct-mapped decoded instruction cache only if profiling
  after hierarchical decoding still shows material decode cost.
- Compare table dispatch or computed goto only if dispatch remains a measured
  bottleneck.

These proposals are experiments, not required final architecture.

## Invariants and ownership boundaries

- `isa_exec_once()` remains the RV32 instruction-step entry point.
- Its external symbol keeps C linkage when implemented in C++.
- Every step still fetches the current raw instruction through the existing
  instruction-fetch and memory interfaces.
- PC, `snpc`, `dnpc`, register, CSR, exception, and invalid-instruction
  behavior remain unchanged.
- Register `x0` remains zero after every instruction.
- Trace, single-step, watchpoint, and DiffTest observe the same architectural
  state transitions.
- No optimization bypasses memory access, MMIO handling, address checks, or
  future translation behavior.
- Profiling instrumentation is optional and absent from the normal hot path.

## Work plan

### 1. Record the RV32 baseline

Use a fixed release-style RV32 interpreter configuration with DiffTest, trace,
watchpoints, and compiler debug mode disabled. Keep only the devices required
by the benchmark.

Record:

- guest instruction count;
- host execution time;
- instructions per second;
- benchmark score where available;
- compiler version, configuration, commit, benchmark data size, and selected
  host timer.

Use MicroBench `train` for the initial baseline. Dhrystone and CoreMark provide
additional workload checks.

As a reference rather than a hard acceptance threshold, an unoptimized RV32
NEMU developed through the normal PA flow typically scores approximately
300-500 on MicroBench `ref` when running on a physical host. A virtual machine
may score lower. Large differences within this broad range can reflect the host
environment rather than the RV32 decoder alone.

### 2. Measure the current decoder

Determine:

- whether the compiler fully folds `pattern_decode()` for constant patterns;
- the generated control flow for the `INSTPAT` chain;
- dynamic opcode and instruction frequencies;
- average and worst pattern checks per guest instruction;
- the proportion of time spent in decode versus instruction semantics and
  surrounding execution overhead.

Profiling counters must be guarded by a dedicated configuration and must not be
used for release performance measurements.

### 3. Migrate the RV32 instruction file to C++

Rename the RV32 implementation from `inst.c` to `inst.cc` and register it as a
C++ source in the RV32 build.

This step changes no decode structure or instruction behavior. It introduces
no STL containers, class hierarchy, dynamic allocation, cache, or new
dispatcher. `isa_exec_once()` retains C linkage.

Compare the C++ build against the baseline and stop if the migration produces
an unexplained regression.

### 4. Introduce hierarchical decoding

Group instructions first by the 7-bit primary opcode. Within each group, select
the operation using only the relevant fields:

- OP and OP-IMM: `funct3` and, where needed, `funct7`;
- LOAD, STORE, and BRANCH: `funct3`;
- SYSTEM: `funct3` and fixed immediate fields;
- JAL, JALR, LUI, AUIPC, and MISC-MEM: their relevant fixed fields.

Keep short instruction semantics directly in the selected branch initially.
Preserve a clear invalid-instruction path for every unsupported encoding.

Run correctness tests and one MicroBench `train` comparison before further
refactoring.

### 5. Simplify RV32 execution primitives

Extract only small, inlineable operations that remove meaningful duplication,
such as immediate decoding and CSR access. Avoid one function per instruction
and avoid abstractions that introduce indirect calls.

Measure again. Keep structural changes that improve clarity, but separate them
from performance claims when they do not produce measurable speedup.

### 6. Re-profile and decide whether to stop

Repeat the decoder measurements after hierarchical decoding.

Stop here if decode is no longer a material bottleneck. Do not add a cache or
alternative dispatcher merely because it was present in the original draft.

### 7. Optionally evaluate a decoded instruction cache

If decode remains significant, evaluate a small fixed-size, direct-mapped
cache owned by the RV32 instruction module.

The cache must:

- perform the normal instruction fetch on every step;
- identify entries with both PC and raw instruction;
- re-decode when the raw instruction changes;
- avoid dynamic allocation;
- start with a small capacity and grow only when measurements justify it;
- remain disabled for execution modes whose address-space identity cannot be
  represented correctly.

Cache invalidation and future MMU behavior require a separate design decision
before enabling the cache for Linux workloads.

### 8. Optionally evaluate dispatch alternatives

Only after re-profiling, compare the hierarchical switch against a handler
table or computed goto. Indirect dispatch is accepted only when it improves
end-to-end performance without reducing observability or portability beyond
the accepted RV32 scope.

## Benchmark procedure

Development comparison:

```bash
make -C am-kernels/benchmarks/microbench ARCH=riscv32-nemu -j 1 run mainargs=train
```

Final confirmation:

```bash
make -C am-kernels/benchmarks/microbench ARCH=riscv32-nemu -j 1 run mainargs=ref
```

Additional workloads:

```bash
make -C am-kernels/benchmarks/dhrystone ARCH=riscv32-nemu -j 1 run
make -C am-kernels/benchmarks/coremark ARCH=riscv32-nemu -j 1 run
```

Run each comparison once by default. Add one or two runs only when host timing
noise could change the conclusion.

The baseline and candidate must use the same host-timer configuration.

If a virtual machine produces an implausibly low MicroBench `ref` score, such
as a single-digit result, treat it as an environment problem before changing
the decoder. In `menuconfig`, change:

```text
Miscellaneous
  Host timer (clock_gettime)
```

Rebuild NEMU and compare it with the default `gettimeofday()` timer. A large
improvement from `clock_gettime()` indicates that the host or virtual-machine
clock source may be dominating the result. Restarting the host or virtual
machine, or correcting its clock-source configuration, may be necessary before
recording the official baseline. The selected timer and the comparison result
must be recorded.

Record results in this form:

| Revision | Workload | Data size | Guest instructions | Host time | Instructions/s | Change |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Baseline | MicroBench | train | 62,779,520 | 2,576,190 us | 24,369,134 | - |
| C++ migration | MicroBench | train | 62,779,454 | 2,609,029 us | 24,062,382 | -1.26% |
| C++ migration (rerun) | MicroBench | train | 62,779,553 | 2,605,412 us | 24,095,825 | -1.12% |
| Hierarchical decode | MicroBench | train | 62,779,553 | 2,602,760 us | 24,120,377 | -1.02% |
| Hierarchical decode (rerun) | MicroBench | train | 62,779,586 | 2,606,067 us | 24,089,782 | -1.15% |
| Baseline (current-env rerun) | MicroBench | train | 62,779,553 | 2,666,042 us | 23,547,848 | - |
| Baseline ref (min of 3) | MicroBench | ref | 1,856,881,453 | 34,561,420 us | 53,726,000 | 643 Marks |
| Hierarchical ref (min of 3) | MicroBench | ref | 1,856,881,453 | 34,467,638 us | 53,872,000 | 644 Marks |
| Hierarchical + timer throttle | MicroBench | ref | 1,856,881,308 | 5,257,191 us | 353,207,883 | 3854 Marks |
| Final head-to-head: baseline (min of 3) | MicroBench | ref | 1,856,881,453 | 34,329,635 us | 54,089,747 | 647 Marks |
| Final head-to-head: rewritten (min of 3) | MicroBench | ref | 1,856,881,334 | 4,926,518 us | 376,915,564 | 4354 Marks |

Final head-to-head (pristine worktree vs rewritten tree, alternating runs,
min host time): **6.97x** host-time reduction, 647 -> 4354 Marks.

Contribution isolation (ref, alternating x3, min host time): the original
INSTPAT decoder with only the timer throttle applied reaches 5.29 s / 351 M
inst/s (~4000 Marks), versus 4.63 s / 401 M inst/s (~4500 Marks) for the
hierarchical decoder with the same throttle. The timer throttle alone
accounts for about 6.5x; hierarchical decoding adds a further 12-14% that was
previously masked by the gettimeofday overhead (decode cost was diluted to
the noise floor while the timer dominated).

## Host-timer bottleneck (found by perf, fixed out of original scope)

`perf record` on a `ref` run showed 74.85% of all host cycles in
`__vdso_gettimeofday` and only 24.66% in `cpu_exec`. Root cause:
`execute()` in `nemu/src/cpu/cpu-exec.c` calls `device_update()` once per
guest instruction, and `device_update()` read the host clock on every call
even though it only acts at `TIMER_HZ` (60 Hz). A `ref` run therefore made
about 1.86 billion `gettimeofday()` calls.

Fix (approved, applied to `nemu/src/device/device.c`): `device_update()` now
polls the host clock only every `DEVICE_UPDATE_INTERVAL` (1024) calls; the
60 Hz device-update semantics are unchanged. This is the "minimal interface
for profiling or cache lifecycle" situation the conditional scope of
`nemu/src/cpu/cpu-exec.c` anticipated, resolved without touching the shared
loop.

Result: `ref` host time 34.56 s -> 5.26 s (6.6x), 353 M guest inst/s, 3854
Marks. A second `perf` run shows 98.5% of cycles in `cpu_exec` and 0.42% in
`__vdso_gettimeofday`. All 35 CPU tests still pass. Note that the timer
overhead was masking the interpreter core: the core was always capable of
~350 M inst/s, so earlier per-instruction-cycle reasoning based on absolute
`inst/s` numbers must be redone against this new baseline.

Baseline environment: x86-64 physical host, clang 22.1.8 with `-O2` and LTO,
commit `e45fbd1`, release-style RV32 interpreter config (DiffTest, trace,
watchpoint, and compiler debug disabled), host timer `gettimeofday()`. MicroBench `train`
scored time 2205.524 ms, total time 2575.462 ms, all benchmarks passed.

Decoder measurement (step 2): the build uses LTO, so `isa_exec_once()` and
the whole `INSTPAT` chain are inlined into `cpu_exec()`. The compiler fully
folds `pattern_decode()` for constant patterns; the disassembled `cpu_exec()`
contains about 1000 host instructions with 82 compares and 72 conditional
branches forming the sequential selection chain. Common instructions are not
ordered to the front, so the average number of checks per guest instruction
remains dependent on source order.

Hierarchical decode measurement (steps 4-6): after the switch-based decoder,
the disassembled `cpu_exec()` shrinks to about 690 host instructions with 41
compares and 8 indirect jumps (compiler-generated jump tables). All 35 CPU
tests pass.

Benchmark methodology warning: this host uses the `powersave` cpufreq
governor (idle at ~1.5 GHz, boost ~3.6 GHz), and short runs start at a
ramping frequency. All `train`-scale comparisons (2.6 s host time) proved
unusable: identical binaries differed by over 50% in host time between runs
minutes apart, and an apparent ~1% regression of the C++ migration as well as
an apparent ~2.3% gain of hierarchical decoding were both frequency-ramp
artifacts. Valid procedure on this host: `ref` scale, 3+ alternating runs per
binary, compare minimum host time.

Before the timer throttle, the pristine decoder and hierarchical decoder tie
at 34.56 s and 34.47 s because host clock polling consumes about three
quarters of all host cycles. This comparison only shows that the decoder
difference was masked by a larger framework bottleneck. With the same timer
throttle applied to both versions, the original decoder reaches 5.29 s while
the hierarchical decoder reaches 4.63 s. The isolated decoder improvement is
therefore approximately 12-14%, in addition to its maintainability benefit.

The timer throttle and hierarchical decoder are both retained. This work stops
without a decoded instruction cache or alternative dispatch implementation
because the accepted changes already provide a clear improvement. Reopening
those optional experiments requires a new measurement-driven decision.

## Validation

Fast RV32 check:

```bash
make -C am-kernels/tests/cpu-tests ARCH=riscv32-nemu -j 1 run ALL=dummy
```

Full RV32 CPU Tests:

```bash
make -C am-kernels/tests/cpu-tests ARCH=riscv32-nemu -j 1 run
```

After enabling the Spike DiffTest configuration, run the same full command with
`-j 1`.

Additional required checks:

- RISC-V ISA tests;
- MicroBench `test`;
- `yield-os`;
- ecall, mret, and CSR behavior;
- invalid-instruction reporting;
- ITrace;
- single-step execution;
- watchpoints.

## Acceptance criteria

- The final RV32 implementation is faster than the recorded baseline on a
  representative long-running workload.
- A claimed improvement is larger than observed host timing noise.
- MicroBench `ref` confirms the final result.
- CPU Tests, RISC-V ISA tests, and Spike DiffTest pass.
- Trace, watchpoint, single-step, exception, and invalid-instruction behavior
  remain available.
- No memory-path optimization is included.
- Performance experiments without clear benefit are removed or reverted.

## Migration and rollback order

Keep these as separate logical changes:

1. baseline and profiling support;
2. behavior-preserving C++ migration;
3. hierarchical decode;
4. host-clock polling throttle;
5. execution primitive cleanup;
6. optional decode cache;
7. optional dispatch experiment;
8. final benchmark record.

Each performance change must be independently revertible. A failed experiment
must not force rollback of the accepted C++ migration or earlier decoder
cleanup.

## Risks

- C++ migration may change symbol linkage or generated code unexpectedly.
- A hierarchical decoder may improve source organization without improving
  host branch prediction.
- Function tables may prevent inlining and regress common instructions.
- A decode cache may cost more in host cache pressure than it saves in decode.
- Profiling instrumentation may distort the hot path.
- Short benchmark runs may be dominated by host scheduling noise.
- Host timer and clock-source performance may dominate results, especially in
  a virtual machine, and can make decoder changes appear more important or less
  important than they are.
- Ignoring future address-space identity would make a PC-only cache incorrect
  once MMU support is added.

## Open questions

- Which benchmark and instruction mix best represent the intended future Linux
  reference workload?
- Should decode caching be reconsidered only after a future Linux workload
  demonstrates that decode remains a material bottleneck?
- Should the C++ migration remain limited to RV32 instruction execution, or is
  there a later measured reason to move part of the shared CPU loop?
