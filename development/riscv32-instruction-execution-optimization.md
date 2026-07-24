# RV32 Instruction Execution Optimization

Status: Draft

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

- `nemu/src/isa/riscv32/inst.c`
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
| Baseline | MicroBench | train | TBD | TBD | TBD | - |
| Candidate | MicroBench | train | TBD | TBD | TBD | TBD |
| Final | MicroBench | ref | TBD | TBD | TBD | TBD |

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
4. execution primitive cleanup;
5. optional decode cache;
6. optional dispatch experiment;
7. final benchmark record.

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
- Does the compiler already optimize the current pattern chain enough that
  hierarchical decoding provides only a maintainability benefit?
- After hierarchical decoding, is a decoded instruction cache still justified?
- Should the C++ migration remain limited to RV32 instruction execution, or is
  there a later measured reason to move part of the shared CPU loop?
