# RV32 Native Execution Engine via In-Place Binary Patching — Postmortem

Status: Rejected — not implemented. This document is kept as design history.

## Summary of the original idea

RV32I+M instruction encodings are almost all legal RV64 instructions with
identical bit patterns. On an RV64 Linux host (VisionFive 2, U74, sv39), an
RV32 bare-metal image (`riscv32-nemu`, fixed-length 4-byte instructions, no C
extension) could in principle be executed natively after a single same-length
patching pass over the loaded image, with three signal handlers (SIGTRAP for
halt, SIGSEGV for MMIO, SIGILL as catch-all) covering the residual semantics.

Target: near-native execution of the exact binary that NEMU/NPC consume, at
roughly a thousand lines of standalone Rust, with no code generation.

The idea was rejected before implementation. Two independent reasons:

1. **Transparent execution is structurally impossible** under Linux on any
   sv39/sv48/sv57 host (see "The address-space wall" below).
2. **The functional need does not exist**: AM's platform abstraction lets any
   program be rebuilt for `ARCH=native` on the VF2 directly. The rv32 binary
   is irreplaceable only as test input for the simulators under development,
   where trust and observability — not speed — are what matter.

## What was verified and still holds

These parts of the analysis are sound and are recorded for reuse:

- **Sign-extension invariant.** Keeping every guest value sign-extended in its
  64-bit host register makes all comparisons (`slt/sltu/slti/sltiu` and
  conditional branches) correct with zero patching. Sign extension is an order
  embedding for both orders: bit31=0 values map to the bottom of the u64 range
  (adding leading zeros), bit31=1 values map to the top (common all-ones
  prefix), and both intra-block and cross-block order are preserved. The
  signed half is plain two's-complement value preservation; the unsigned half
  is the non-obvious part and must be checked explicitly (e.g.
  `0x7FFFFFFF` vs `0x80000000` map to `0x00000000_7FFFFFFF` and
  `0xFFFFFFFF_80000000`, which still compare the same way under u64 order).
- **W-form substitution.** `addw`/`sllw`/... compute the low 32 bits and
  sign-extend the result, which is exactly RV32 semantics and exactly
  maintains the invariant. `mul`/`div`/`rem` variants also have W-forms.
- **Empirical scan of privileged instructions** in the actual target images:
  cpu-tests and hello contain zero `csr`/`ecall`/`mret`; yield-os contains
  exactly 9 (`csrw mtvec`, `ecall`, `csrr mcause/mstatus/mepc`,
  `csrw mstatus` x2, `csrw mepc`, `mret`). A minimal shadow-CSR model of
  {mtvec, mcause, mstatus, mepc} would have sufficed for CTE programs.
- **Stack initialization**: AM's `start.S` sets `sp` itself from the linker
  script (`_stack_pointer` = bss end + 0x8000); an engine only needs to set pc
  and zero the registers to match NEMU's reset state.
- **The trap-handling machinery is feasible**: signal handlers can rewrite the
  saved context through `ucontext_t` (`gregs[0]` = pc, `gregs[n]` = xn), and
  `sigreturn` restores whatever the handler leaves there — the same mechanism
  yuzu NCE uses for SIGUSR2/SIGURG thread injection/preemption.

## Difficulty 1 (solvable): XLEN-divergent arithmetic

`add` on RV64 wraps at 64 bits, RV32 semantics require wrap at 32. Fixed by
the W-form patch plus the sign-extension invariant above. `mulh` family has no
W-form and must be patched to a field-preserving illegal encoding and emulated
in SIGILL (patching to all-zeros destroys rd/rs1/rs2 — the original spec's
`0x00000000` choice was wrong; it also decodes as the 16-bit `c.unimp` on a
C-capable U74).

## Difficulty 2 (solvable but real): privileged instructions

The target is `rv32im_zicsr`, and CTE-using programs execute `ecall`, CSR
accesses, and `mret`. On the host, U-mode `ecall` is **the Linux syscall
instruction itself** — it does not trap, it performs a real syscall with
guest-controlled arguments (yield-os's `yield()` issues `ecall` with `a7=-1`,
which would silently return `-ENOSYS`). This is exactly the silent-wrong-result
class the goals forbade. CSR/`mret` do trap (SIGILL). The yuzu-derived fix is
load-time patching of these sites to trampolines or illegal encodings, with a
shadow M-mode model in the runtime. Real work, but bounded (9 sites in
yield-os).

## Difficulty 3 (fatal): the address-space wall

### The host layout constraint

Linux on RISC-V splits the canonical virtual address space by the top of the
svN range (kernel `Documentation/arch/riscv/vm-layout.rst`):

| mode | user space | kernel space |
|---|---|---|
| sv39 | `0x00000000_00000000` – `0x0000003F_FFFFFFFF` | `0xFFFFFFC0_00000000` – `0xFFFFFFFF_FFFFFFFF` |
| sv48 | `0x0` – `0x00007FFF_FFFFFFFF` | `0xFFFF8000_00000000` – ... |
| sv57 | `0x0` – `0x00FFFFFF_FFFFFFFF` | `0xFF000000_00000000` – ... |

Under every mode, an address whose bits 63:32 are all ones is in the kernel
half. User `mmap` there always fails.

### Two pointer forms arise unavoidably

Guest RAM sits at `0x80000000` (bit 31 = 1). This is not a local project
choice: it is the ecosystem-wide RISC-V convention — the QEMU virt machine's
DRAM base and reset vector, inherited by OpenSBI's jump target, the Linux
riscv kernel load address, xv6-riscv's KERNBASE, and therefore by NEMU's
`CONFIG_MBASE`, AM's linker scripts, and NPC's address decoding. No
re-linking trick can move it without rebuilding the very artifact the engine
existed to run, which would dissolve its only remaining purpose. Executing
the image in place at its natural address is mappable, but then pointers
reach registers by two different routes:

- **pc-derived** (`auipc`/`jal`, including every `la`): the host adds to the
  real 64-bit pc, producing the zero-extended form `0x00000000_8xxxxxxx`.
- **memory-loaded** (`lw`): RV64 `lw` sign-extends, producing
  `0xFFFFFFFF_8xxxxxxx`.

For `auipc` output to equal the sign-extended form, code would have to be
mapped at `0xFFFFFFFF_80000000` itself — kernel half, impossible. So the two
forms coexist and neither can be eliminated.

### Minimal example A: `ret` jumps into the kernel half

```asm
# caller prologue/epilogue, completely ordinary code
sw   ra, 12(sp)          # stores low 32 bits of 0x00000000_80000123
lw   ra, 12(sp)          # reads back 0x80000123, sign-extends:
                         # ra = 0xFFFFFFFF_80000123
ret                      # jalr x0, 0(ra): instruction fetch at
                         # 0xFFFFFFFF_80000123 -> page fault -> SIGSEGV
```

Recoverable in a handler (truncate, fix `gregs[0]`, sigreturn) but a signal
round trip per return destroys the near-native goal. The hot case can be
patched (`lw ra` -> `lwu ra` is same-length and safe by the ABI), but spilled
function pointers and data pointers remain on the slow path.

### Minimal example B: the unguardable case — cross-form comparison

```c
// guest semantics: cb == &my_handler is true
if (cb == &my_handler) { ... }
```

```asm
lw   a5, ...          # cb, round-tripped through memory: 0xFFFFFFFF_80000abc
auipc a4, ...         # ┐ &my_handler, pc-derived: 0x00000000_80000abc
addi a4, a4, ...      # ┘
beq  a5, a4, ...      # 64-bit compare: NOT equal -> wrong branch, silently
```

No memory access, no fault, no hook point. All three escapes are closed:

- eliminate the zero-extended form → requires code at `0xFFFFFFFF8...`
  (kernel half, impossible under every sv mode);
- eliminate the sign-extended form → must patch pointer loads to `lwu`, but a
  `lw` encoding cannot be statically classified as pointer vs data;
- intercept the comparison → `beq` never traps.

### Why "patch every load to zero-extending" fails

Patching all `lw`->`lwu` (and `lb`->`lbu`, `lh`->`lhu`) makes pointers uniform
but breaks signed data comparison, which cannot be patched same-length:

```asm
# guest: t0 = -1, t1 = 1;  slt a0, t0, t1 must be 1
# with zero-extended values: t0 = 0x00000000_FFFFFFFF (a huge positive),
# slt (signed 64-bit) yields 0. Wrong, and silently so.
```

Sign-extended data (needed by `slt`) and zero-extended pointers (needed by
the mappable address) are incompatible demands on the same load instructions.

### The structural conclusion

NEMU and qemu-user achieve transparency precisely by *not* sharing the host's
address space and register width. This engine's entire premise was "close
enough to share"; the sharing is exactly where transparency dies. yuzu NCE
never faces this because its guest is already a 64-bit process whose pointers
live in the low half from the start — and its answer to 32-bit guests was to
fall back to JIT, which in hindsight was the same wall.

## What a pragmatic (non-transparent) version would have looked like

Recorded in case the idea is ever revisited with relaxed goals:

- execute in place at `0x80000000`; no mirror mapping, no arena;
- sign-extension invariant for data, W-form patching, `mulh` via
  field-preserving illegal encoding + SIGILL emulation;
- `lw ra` -> `lwu ra` patch; SIGSEGV truncate-and-emulate fallback for the
  remaining form-S dereferences;
- `ecall`/CSR via trampolines or SIGILL with shadow {mtvec, mcause, mstatus,
  mepc};
- cross-form comparison risk accepted as documented, audited empirically;
- validation: cpu-tests halt codes vs NEMU, microbench Marks, yield-os.

## Addendum: how the "real" solution does it (hardware compat mode)

ARM and x86 implement 32-bit compatibility **in silicon**: ARMv8 has a whole
second execution state (AArch32 at EL0); x86-64 has compatibility mode via a
code-segment bit. RISC-V has the same idea in the privileged spec: writable
`sstatus.UXL` lets U-mode execute with XLEN=32. Linux merged riscv
`CONFIG_COMPAT` (5.19) to run rv32 user binaries on it; T-Head modified their
hardware to implement UXL=32 ([RISC-V International blog](https://riscv.org/blog/run-32-bit-applications-on-64-bit-linux-kernel-liu-zhiwei-guo-ren-t-head-division-of-alibaba-cloud/)).

Measured on the VF2 (2026-09, kernel 6.12.5-starfive, U74-mc, sv39): a
statically linked rv32 ELF exits with `Exec format error` despite the kernel
having `CONFIG_COMPAT=y` and `CONFIG_COMPAT_BINFMT_ELF=y` — i.e. the U74 does
not implement writable UXL. The transparent engine exists as a hardware
feature; this chip simply does not contain it.

Note that the hardware cost is small precisely because RV64 already contains
the 32-bit datapaths: the W-form instructions (addw/sllw/...) are the
32-bit-wrap-plus-sign-extend paths, and UXL=32 is mostly muxes selecting
those paths, shamt width, address truncation, and CSR widths — a mode wire
through the pipeline, not a second ALU.

## Lessons

- **The SW/HW boundary is the real design decision.** The same feature can be
  implemented on either side, but each side pays differently: hardware gets
  per-instruction semantic switching for free (a mode bit is a physical wire
  every instruction passes through); software can only act at interception
  points (traps/faults). RV32-on-RV64 compatibility requires per-instruction
  semantics flips on *every load and every comparison* — a cost only the
  hardware side can afford. Our software approach tried to replicate a wire
  that only silicon can route.
- **Borrowed techniques travel with their premises.** yuzu's patch /
  trampoline / signal-handler toolbox works because its premise (same width,
  same ISA) makes divergences exceptional. Under a width mismatch the
  divergence is structural — present in every load — and a toolbox built for
  exceptions cannot fix the norm.
- **Agent-drafted specs need empirical verification of every load-bearing
  fact.** The original spec's "mirror-map at `0xFFFFFFFF80000000`" was listed
  as a *confirmed decision* yet was never viable on any RISC-V Linux. One page
  of the kernel vm-layout doc would have killed it at draft time.
- **Check host-behavior assumptions first** (mappable VA range; what U-mode
  `ecall`/CSR instructions actually do) before designing anything that depends
  on them.
- **Disassembly beats reasoning about what binaries contain** — the objdump
  scan settled the CSR scope question in minutes.
- **The transparency goal was the fragile part.** Performance goals degrade
  gracefully; a silent-semantic-divergence goal fails structurally.
