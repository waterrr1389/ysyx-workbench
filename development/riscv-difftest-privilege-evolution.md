# RISC-V DiffTest and Privilege-State Evolution

Status: Completed

## Context

The RV32 implementation is evolving from a machine-mode teaching model toward a system capable of supporting a Linux boot path. This requires explicit privilege state, architecturally correct trap transitions, and a DiffTest boundary that can evolve without depending on private structure layouts.

The validation topology has two primary paths:

```text
Spike reference <- DiffTest -> NEMU DUT
NEMU reference  <- DiffTest -> NPC DUT
```

NEMU is therefore the long-term DiffTest hub. The current change covers only
the Spike-to-NEMU path. NPC adoption of the canonical ABI is a separate
evolution milestone and is not required to remain compatible during this
change.

## Observed baseline

On 2026-07-25, the user reported that the full CPU regression suite passed with:

```sh
make -C am-kernels/tests/cpu-tests ARCH=riscv32-nemu -j 1 run
```

A focused `dummy` test also passed with Spike DiffTest enabled:

```sh
make -C am-kernels/tests/cpu-tests ARCH=riscv32-nemu -j 1 run ALL=dummy
```

`yield-os` reaches the trap entry under Spike DiffTest and then exposes an architectural mismatch:

- NEMU currently models `ecall` as cause 8.
- Spike produces cause 11 when `ecall` executes in M-mode.
- NEMU currently records the sequential next PC in `mepc`.
- The privileged architecture requires `mepc` to identify the `ecall` instruction itself.

These observations establish a working ordinary-instruction baseline and a focused privileged-state failure.

CPU tests with DiffTest enabled must use `-j 1`. Omitting `ALL` runs the full
suite; setting `ALL=<test>` selects one test.

## Goals

- Decouple DiffTest data exchange from NEMU `CPU_state` and Spike `state_t`.
- Detect stale or incompatible DiffTest shared libraries before execution.
- Make adapter mappings reviewable and semantic mismatches visible through
  focused integration validation.
- Introduce current privilege as explicit architectural state.
- Record machine trap-entry and `mret` requirements for a later privileged
  execution milestone.
- Give CTE responsibility for advancing `mepc` after handled environment calls.
- Preserve small, independently verifiable migration and rollback boundaries.

## Non-goals

The initial change does not provide complete Linux support. It does not yet commit to implementing:

- the complete S-mode CSR set;
- trap delegation through `medeleg` or `mideleg`;
- Sv32 address translation or TLB behavior;
- PMP;
- platform interrupt controllers;
- OpenSBI or Linux boot integration;
- backward compatibility with third-party prebuilt DiffTest libraries.

The design must leave room for these features without claiming they are part of the initial implementation.

## Confirmed decisions

### Documentation and process

- This work uses architecture and evolution mode.
- Discussion and specification precede implementation.
- This lightweight `development/` directory is the canonical design record for the change.
- Implementation must remain separated from review and validation.

### Validation topology

- Spike validates NEMU.
- NEMU remains the intended future reference for NPC.
- NPC migration is outside the current implementation and validation scope.
- The updated NEMU reference shared library does not preserve compatibility
  with the current NPC caller.
- The first ABI does not need partial-capability negotiation.

### DiffTest ABI ownership

- NEMU's public DiffTest interface owns the canonical RV32 state contract.
- The ISA-specific header will live at `nemu/include/difftest/arch/riscv32.h`.
- Spike must include this header instead of maintaining a copied state
  structure.
- A later NPC migration must consume the same canonical header or define a new
  accepted ABI evolution; it must not copy the structure.
- Generic direction constants and scalar ABI-query function types remain in
  NEMU's generic DiffTest header.
- The first wire representation is a named, C-compatible structure.
- The first ABI is an exact profile: every declared field is mandatory, with no
  runtime valid-field or capability mask.
- Internal backend state must cross the ABI only through explicit, field-by-field
  adapters.
- `difftest_regcpy` remains the single bidirectional register-transfer entry
  point, but uses the canonical RV32 state pointer and a fixed-width direction
  argument instead of `void *` and `bool`.
- Shared-library initialization queries both ABI version and state size before
  any register transfer.

### Architectural direction

- Current privilege is necessary architectural state for the Linux path.
- An environment call cause depends on the originating privilege mode.
- For `ecall`, hardware state records the faulting instruction address in `mepc`.
- Software that resumes after the environment call must advance the saved `mepc`.
- The current milestone adds explicit privilege and privilege-dependent
  environment-call causes, but defers complete `mstatus` trap stacking and
  `mret` privilege restoration.
- This simplification is valid only while the exercised AM path remains in
  M-mode and does not test cross-privilege traps.

## DiffTest boundary

### Layering

```text
NEMU CPU_state -- adapter --+
                            |
                      RV32 wire state
                            |
Spike state ----- adapter --+
```

The wire state defines the current shared binary contract between NEMU and
Spike. Each adapter converts between architectural values and one
implementation's private representation.

The adapter does not make private structures layout-compatible. It removes that requirement:

- NEMU accesses NEMU fields using the NEMU compiler's layout.
- Spike accesses CSR objects through `read()` and `write()`.
- Only the wire state crosses the shared-library boundary.

The later NPC path will add its own adapter as an independent migration:

```text
NPC state -- future adapter -- RV32 wire state -- NEMU adapter -- CPU_state
```

### Wire representation

The first representation is a named, C-compatible RV32 structure. Every slot is
`uint32_t`, in this exact order:

| Field | Byte offset | Size |
| --- | ---: | ---: |
| `gpr[32]` | 0 | 128 |
| `pc` | 128 | 4 |
| `priv` | 132 | 4 |
| `mstatus` | 136 | 4 |
| `mtvec` | 140 | 4 |
| `mepc` | 144 | 4 |
| `mcause` | 148 | 4 |

The total state size is 152 bytes. The 32 GPR slots always include `x0`; export
must produce zero for `gpr[0]`, and import must not make `x0` writable. RV32E
providers export zero for slots 16 through 31.

Privilege uses the architectural numeric encoding in a `uint32_t` slot rather
than a stored C or C++ enum: U=0, S=1, and M=3.

The wire representation must not contain:

- `word_t` or configuration-dependent integer aliases;
- pointers;
- C++ standard-library types;
- bitfields;
- stored C or C++ enums;
- implementation-owned objects.

The structure must not use packed layout. Its total size and every listed field
offset must be checked with compile-time assertions in both C and C++
translation units.

### Version policy

The first version requires exact compatibility:

- the caller resolves and invokes `difftest_get_abi_version()`, returning
  `uint32_t`;
- the caller resolves and invokes `difftest_get_state_size()`, returning
  `uint32_t`;
- version or size mismatch aborts initialization with an explicit diagnostic;
- a missing query symbol also aborts initialization before `difftest_regcpy`;
- incompatible state changes increment the ABI version;
- all providers and consumers participating in the current NEMU-to-Spike path
  are rebuilt together.

Backward-compatible partial-size exchange, capability masks, TLV encoding, and a versioned function table are deferred until a concrete requirement justifies them.

### Register-transfer entry point

The first ABI retains one bidirectional register-transfer entry point. Its
contract uses:

- a pointer to the canonical RV32 wire-state type;
- a `uint32_t` direction argument;
- direction value 0 for `DIFFTEST_TO_DUT`;
- direction value 1 for `DIFFTEST_TO_REF`.

The canonical RV32 header owns the fixed-width register-copy function type.
NEMU's generic DiffTest header remains the single owner of direction constants.
Providers and consumers must not redeclare either contract locally. Splitting
the entry point into separate get/set symbols is deferred because it would
expand this RV32 state migration into a general DiffTest API redesign.

### Adapter ownership

Each backend owns explicit import and export adapters between its private state
and the wire state:

- NEMU adapters access `CPU_state`;
- Spike adapters access registers and CSRs through Spike's public state
  operations.

The generic loader handles symbol resolution, compatibility checks, and wire
state transfer. It must not interpret `priv`, CSRs, or other architecture
fields.

Private state and wire state must not be connected by casts, layout aliasing, or
whole-structure copies. A private-layout change is local to its backend as long
as that backend's adapters continue to satisfy the wire contract.

## Adapter correctness

ABI version and layout assertions do not prove that an adapter handles every
field. The initial migration does not introduce a standalone adapter unit-test
framework because Spike state is expensive to isolate from its execution
environment.

Every V1 field is mandatory. There is no runtime valid-field mask, because NEMU
and Spike use one exact active profile.

The minimum verification is:

- compile every provider and consumer against the canonical header;
- review import and export adapters field by field;
- reject structure casts, layout aliasing, and whole-structure copies;
- verify the ABI-version and state-size rejection path;
- run focused Spike DiffTest cases that exercise the privileged fields;
- run the NEMU regression paths.

### Comparison coverage

State synchronization and per-instruction comparison are different responsibilities:

- synchronization transfers all state required to initialize or resynchronize a backend;
- comparison checks the architectural state required by the active milestone.

All V1 fields are synchronized. The current milestone compares these fields
after each instruction:

- all GPRs;
- `pc`;
- `priv`;
- `mtvec`;
- `mepc`;
- `mcause`.

`mstatus` is synchronized but is not yet compared after every instruction.
Spike updates `MPP`, `MPIE`, and `MIE` as part of architectural trap and `mret`
behavior even without external interrupts. Enabling per-instruction `mstatus`
comparison is deferred until NEMU implements those transitions. NPC comparison
policy belongs to its later migration.

## Context and assembly layout

The AM `Context` and `trap.S` frame genuinely require an exact shared layout.
This is separate from the DiffTest ABI.

The layout contract uses one preprocessor-only constants header shared by C and
assembly. The C side checks every field offset and the complete size using
`offsetof` and `sizeof` static assertions. The assembly side consumes the same
constants rather than maintaining independent calculations.

The header is local to the current platform implementation:

```text
abstract-machine/am/src/riscv/nemu/context-offset.h
```

It uses `RISCV_CONTEXT_`-prefixed macros and is included by this platform's
`cte.c` and `trap.S`. Promoting the contract to the public architecture include
directory, or migrating the NPC trap implementation to it, is deferred until a
separate cross-platform requirement exists.

The complete context contains:

- the fixed GPR slots;
- `mcause`;
- `mstatus`;
- `mepc`;
- `pdir`.

Assembly saves or restores the hardware-state fields but does not interpret
`pdir`. It must still reserve the `pdir` slot. Therefore:

- `CONTEXT_SIZE` equals `sizeof(Context)`;
- trap entry allocates the complete context;
- `kcontext()` places the complete context immediately below `kstack.end`;
- after assembly restores a constructed context, the initial kernel-thread
  stack pointer equals `kstack.end`.

Generated offsets are deferred because the small fixed structure does not
justify adding target-generated files and build dependencies.

## Privilege-state model

The privilege model must distinguish current privilege from `mstatus.MPP`.

### Current milestone

The first privilege-state change is intentionally limited to:

- an explicit `uint8_t` current-privilege field in NEMU private state;
- reset into M-mode;
- environment-call cause selection from current privilege;
- DiffTest synchronization and comparison of current privilege.

Named integer constants use the architectural encodings U=0, S=1, and M=3.
The private state field is not a stored C enum. The DiffTest adapter widens it
to the wire state's `uint32_t` slot and rejects imported values other than 0,
1, or 3 rather than truncating or normalizing them. Environment-call cause
selection uses an explicit privilege switch rather than arithmetic on the
encoding.

Complete CSR permission checking is not part of this milestone. The model must
not claim correct execution of untrusted S-mode or U-mode software until those
checks and the required trap transitions are implemented.

### Later privileged execution milestone

Before cross-privilege traps or a Linux boot path are supported, the following
state transitions require a separate accepted specification:

### Reset

- current privilege becomes M;
- reset values of relevant `mstatus` fields are defined.

### Trap into M-mode

- `MPP` records the originating privilege;
- `MPIE` records `MIE`;
- `MIE` is cleared;
- current privilege becomes M;
- `mepc` records the faulting or interrupted instruction address;
- `mcause` records the trap cause;
- execution transfers through `mtvec`.

### `mret`

- current privilege is restored from `MPP`;
- `MIE` is restored from `MPIE`;
- `MPIE` becomes one;
- `MPP` becomes the least-privileged supported mode;
- `MPRV` behavior is applied when leaving M-mode;
- execution resumes from `mepc`.

Synchronous exceptions use the same privileged trap-entry stacking rules as
interrupts. The fact that NEMU implements the transition in
`isa_raise_intr()` does not change its architectural role. The precise
supported-mode set and invalid-state handling remain open for that later
milestone.

## Environment-call ownership

The planned responsibility boundary is:

### NEMU

- derive the environment-call cause from current privilege;
- save the `ecall` instruction address in `mepc`;
- transfer execution to `mtvec`;
- defer complete `mstatus` trap stacking to the later privileged execution
  milestone.

### CTE

- recognize environment-call causes 8, 9, and 11;
- classify the environment call as yield or syscall;
- advance the original context's `mepc` by four before invoking the registered
  handler;
- leave unrelated interrupts and exceptions unchanged;
- return the selected context to the assembly restore path.

`ECALL` is a 32-bit instruction, so this increment is independent of compressed-instruction support.

## Implementation contract

### ABI names and compatibility

The canonical type is named `riscv32_difftest_state_t`. The canonical header
defines:

- `RISCV32_DIFFTEST_ABI_VERSION` as version 1;
- the complete wire structure;
- compile-time size and offset assertions;
- the fixed-width register-copy function type;
- C-linkage declarations when included from C++.

Only the RV32 DiffTest build selects this ABI. RV64 and non-RISC-V builds retain
their existing register-copy contracts in this change. `difftest_memcpy`,
`difftest_exec`, `difftest_raise_intr`, and `difftest_init` retain their current
signatures.

The two query entry points are available before `difftest_init()` and do not
depend on initialized simulator state. NEMU resolves them immediately after
opening the reference shared library. Missing symbols, a version other than 1,
or a state size other than 152 bytes abort initialization with a diagnostic
that includes the expected and observed values when available.

### NEMU adapter boundary

RV32 conversion between `CPU_state` and `riscv32_difftest_state_t` is
implemented in the RISC-V ISA layer rather than by field access in the generic
loader. The generic NEMU DiffTest code:

- asks the ISA adapter to export local state before `DIFFTEST_TO_REF`;
- receives wire state from `DIFFTEST_TO_DUT`;
- asks the ISA adapter to import it into a local `CPU_state` before comparison.

The adapter explicitly handles all 32 wire GPR slots. For RV32E it transfers
the implemented slots and exports zero for the remaining slots. Import cannot
make `x0` writable and rejects invalid privilege encodings.

### Spike adapter boundary

Spike removes its private copied DiffTest structure and uses the canonical
header. Its adapter:

- accesses GPRs through the register-file API;
- accesses CSRs through CSR `read()` and `write()` operations;
- reads current privilege from Spike state;
- applies imported privilege through Spike's privilege-setting operation after
  validating the wire encoding;
- transfers PC explicitly.

No Spike private object or pointer crosses the shared-library boundary.

### Minimal NEMU trap behavior

The current `isa_raise_intr()` remains a software implementation of trap entry,
but this milestone deliberately limits it to:

- copying the supplied cause into `mcause`;
- copying the supplied instruction address into `mepc`;
- returning `mtvec`.

It does not implement `mstatus` stacking or privilege transitions. The `ecall`
instruction selects cause 8, 9, or 11 with an explicit switch on current
privilege and passes the current instruction address rather than the sequential
next PC.

### Affected files

The expected implementation surface is:

- new `abstract-machine/am/src/riscv/nemu/context-offset.h`;
- `abstract-machine/am/src/riscv/nemu/cte.c`;
- `abstract-machine/am/src/riscv/nemu/trap.S`;
- new `nemu/include/difftest/arch/riscv32.h`;
- NEMU generic DiffTest declarations, loader, and reference provider;
- the RV32 ISA state definition, initialization, adapter, comparison, trap, and
  instruction files;
- `nemu/tools/spike-diff/difftest.cc`.

NPC files, complete CSR permission logic, and complete trap/`mret` transitions
are outside this implementation surface.

## Migration order

The order is:

1. Complete AM kernel-context switching and establish the shared
   C/assembly layout contract.
2. Introduce the canonical V1 wire contract, ABI queries, and loader checks.
3. Migrate NEMU and Spike to explicit adapters without changing CPU behavior
   other than adding synchronized current privilege.
4. Validate focused and full CPU regressions.
5. Correct the environment-call cause and saved PC in NEMU.
6. Advance `mepc` in CTE for handled environment calls.
7. Validate context switching under Spike DiffTest.
8. Specify and implement complete trap-entry, `mret`, and CSR privilege
   behavior before exercising cross-privilege software.

The intended commit boundaries are:

1. AM kernel context switching and the complete context-layout contract;
2. the atomic RV32 DiffTest ABI migration across NEMU and Spike;
3. NEMU environment-call cause and saved-PC semantics;
4. CTE resume-after-environment-call behavior.

The NEMU and CTE environment-call commits form an ordered pair: the NEMU commit
is independently validated against Spike at the architectural trap boundary,
while the following CTE commit restores the complete `yield-os` path. NPC
migration, unrelated NPC tracing changes, and existing local work must not be
included.

These are logical commit boundaries. Implementation will keep the changes
separable, but it will not create Git commits without separate user
authorization.

## Risks

- A canonical wire structure can still drift if consumers copy rather than include its header.
- Version checks do not detect an adapter that silently omits a field.
- Spike may normalize legal CSR writes; validation must use the actual values
  returned by Spike rather than assuming raw storage behavior.
- Adding privilege without complete state transitions is safe only under the
  explicitly M-mode-only milestone boundary.
- Correcting `mepc` in NEMU without advancing it in CTE can repeatedly execute `ecall`.
- Correcting only the environment-call cause can move the DiffTest failure to the later `mepc` read.
- Mixing the ABI migration with trap semantics would make regressions difficult to attribute.

## Acceptance criteria

Implementation begins only after this Draft is accepted. Completion requires:

- compile-time wire-layout checks;
- early rejection of an intentionally mismatched shared library;
- field-by-field adapter review;
- a focused `dummy` CPU test;
- the full CPU regression suite;
- `yield-os` context switching under Spike DiffTest.

The active NEMU configuration must contain both:

```text
CONFIG_DIFFTEST=y
CONFIG_DIFFTEST_REF_SPIKE=y
```

Before rebuilding the Spike provider for the ABI migration, preserve the
current provider as an intentionally stale V0 library:

```sh
stale_diff_dir=$(mktemp -d /tmp/ysyx-difftest-abi.XXXXXX)
cp nemu/tools/spike-diff/build/riscv32-spike-so \
  "$stale_diff_dir/riscv32-spike-so-v0"
```

The validation sequence is:

```sh
make -C nemu -j$(nproc)
make -C nemu/tools/spike-diff GUEST_ISA=riscv32
nm -D nemu/tools/spike-diff/build/riscv32-spike-so |
  rg 'difftest_get_(abi_version|state_size)|difftest_regcpy'
make -C am-kernels/tests/cpu-tests \
  ARCH=riscv32-nemu -j 1 run ALL=dummy
make -C am-kernels/tests/cpu-tests \
  ARCH=riscv32-nemu -j 1 run
```

CPU tests must remain serial. Omitting `ALL` runs the full suite.

Run the rebuilt NEMU directly against the preserved V0 provider:

```sh
nemu/build/riscv32-nemu-interpreter \
  --diff="$stale_diff_dir/riscv32-spike-so-v0" \
  -b am-kernels/tests/cpu-tests/build/dummy-riscv32-nemu.bin
```

This command must fail before register transfer with a diagnostic identifying
the missing ABI query symbol. A separately built wrong-version or wrong-size
provider is unnecessary for this milestone because the missing-symbol path
proves rejection of the actual stale ABI.

With Spike DiffTest enabled, exercise the trap and first context-switch path:

```sh
make -C am-kernels/kernels/yield-os ARCH=riscv32-nemu
timeout 3s make -C am-kernels/kernels/yield-os \
  ARCH=riscv32-nemu run
```

This configuration has `CONFIG_DEVICE` disabled, so the expected boundary is
the new thread's first serial MMIO access. Before that access, execution must
complete the M-mode environment call, trap entry, context selection, context
restore, `mret`, and transfer to the new thread without a DiffTest mismatch.

Continuous scheduling output is verified separately with a temporary native
NEMU configuration that disables DiffTest and enables the device model. Preserve
and restore the active `.config`, synchronize Kconfig after each change, and
run:

```sh
timeout 3s make -C am-kernels/kernels/yield-os \
  ARCH=riscv32-nemu run
```

The timeout exit is expected. Success means repeated `?` output with no panic.
The output remains `?` because passing `arg` to a new kernel context is outside
the current task.

Before reporting completion:

```sh
git diff --check
git status --short
```

Exact result summaries must be added before the document becomes `Completed`.

## Validation results

Validation completed on 2026-07-25:

- `make -C nemu -j$(nproc)` completed successfully with the restored Spike
  DiffTest configuration.
- `make -C nemu/tools/spike-diff GUEST_ISA=riscv32` completed successfully.
  Spike emitted its existing `log_file.h` ignored-attributes warning.
- `make -C nemu/tools/spike-diff GUEST_ISA=riscv64` also compiled, confirming
  that the retained RV64 branch was not broken.
- `nm -D` showed exported `difftest_get_abi_version`,
  `difftest_get_state_size`, and `difftest_regcpy` symbols.
- NEMU rejected the preserved V0 Spike provider before executing any guest
  instruction, reporting the missing `difftest_get_abi_version` symbol.
- The focused `dummy` CPU test passed with Spike DiffTest.
- The serial full-suite command passed all 35 CPU tests with Spike DiffTest.
- Spike DiffTest followed `yield-os` through cause 11 at the environment call,
  trap handling, `mret`, and entry into the selected kernel thread without a
  state mismatch. Execution then stopped at serial address `0xa00003f8`, as
  expected with `CONFIG_DEVICE` disabled.
- With a temporary native configuration using `CONFIG_DEVICE=y` and DiffTest
  disabled, the three-second `yield-os` run timed out as expected after
  approximately 39.5 million guest instructions and produced 79 `?`
  characters.
- The original Spike DiffTest `.config` and generated Kconfig headers were
  restored and NEMU was rebuilt afterward.
- `git diff --check` reported no whitespace errors.

## Deferred questions

1. Which privilege modes and invalid-state behavior belong to the later
   cross-privilege transition milestone?
2. When should NPC adopt the canonical RV32 ABI and expose its architectural
   state?

## References

- RISC-V Instruction Set Manual, Volume II: Privileged Architecture, sections 3.1.14, 3.1.15, 3.3.1, 3.3.2, and 3.4.
- Local NEMU, Spike DiffTest, NPC DiffTest, AM CTE, and trap-entry implementations are the repository-specific evidence for this document.
