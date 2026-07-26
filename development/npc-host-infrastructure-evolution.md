# NPC Host Infrastructure Evolution

Status: In Progress

## Context and observed baseline

NPC's host-side simulator is written and built as C++, but some source files
still use `.c` names and preserve code copied from NEMU.

The current DiffTest path in `npc/csrc/difftest/difftest.c` independently owns:

- the dynamic-library handle and symbol table;
- reference initialization;
- image and initial-state synchronization;
- the per-instruction reference execution sequence;
- reference and DUT state collection;
- mismatch handling.

This duplicates the protocol stages in NEMU's DiffTest DUT implementation.
Changes to symbol types, ABI validation, initialization order, state layout, or
skip behavior can therefore require synchronized edits in both modules.

The canonical RV32 DiffTest ABI now lives in
`nemu/include/difftest/arch/riscv32.h`. NPC has not migrated to this ABI and
still declares a private GPR-plus-PC state structure and the legacy register
copy signature.

Trace selection is currently split between Make variables, compiler
definitions, and a manually maintained fallback header. The active worktree
already has preliminary `ITRACE`, `FTRACE`, and `MTRACE` Make variables, but
there is no persistent, validated configuration profile.

A candidate `nemu/.clang-format` has been placed in the worktree for
evaluation. It is currently ignored by `nemu/.gitignore`, is not tracked, and
has not been approved as repository policy. Full-file formatting still
produces unrelated historical changes even when copyright comments and include
order are preserved.

## Goals

- Make the DiffTest shared-library protocol have one maintained
  implementation.
- Keep NEMU and NPC state access behind separate DUT adapters.
- Make NPC consume the canonical RV32 DiffTest ABI instead of copying it.
- Replace manual trace-header editing with a validated build configuration.
- Keep trace-disabled builds free of unnecessary trace work.
- Establish a formatter configuration without mass-formatting historical
  source files or changing copyright headers.
- Preserve small migration steps with independent build and rollback
  boundaries.

## Non-goals

- Redesigning the exported DiffTest `.so` C ABI.
- Generalizing DiffTest for ISAs other than the active RV32 profile.
- Adding new architectural state or implementing missing NPC privileged
  behavior.
- Making NPC and NEMU internal CPU state representations identical.
- Rewriting NPC simulation, monitor, trace, or mismatch-reporting behavior.
- Formatting all existing NEMU, NPC, or AM source files.
- Introducing a general build framework for every workbench subproject.
- Enabling all trace facilities at runtime in performance-oriented builds.

## Affected modules and interfaces

Primary modules:

- `nemu/include/difftest/`
- `nemu/src/cpu/difftest/`
- `npc/csrc/difftest/`
- `npc/include/difftest/`
- `npc/Makefile`
- future NPC configuration profiles and generator

Supporting tooling:

- `nemu/.clang-format`
- a generated NPC configuration header under `npc/build/`

The exported DiffTest shared-library symbols remain C ABI entry points. C++
classes are host-side implementation details only.

## Confirmed decisions

### Scope and process

- The implementation follows this specification in independently verifiable
  commits.
- NEMU remains the owner of the canonical RV32 DiffTest state contract.
- NPC migration must consume the canonical contract instead of copying its
  fields, constants, or register-copy signature.
- Existing unrelated NPC, AM, and trace worktree changes must be preserved.
- Implementation and review remain separate.

### DiffTest ownership

- Dynamic-library loading is host-side C++ work and may use a class.
- The loader must own the library handle and typed symbol resolution.
- ABI version and state size must be validated before register transfer.
- The caller-facing interface should express state transfer direction through
  separate get-state and set-state operations rather than repeated raw
  direction arguments.
- NEMU and NPC retain separate adapters for their private DUT state.
- Hardware sampling through `read_gpr()` and `top->pc` remains NPC-owned.
- NEMU architectural-state access remains NEMU-owned.
- Mismatch formatting and simulator termination remain DUT-owned.

### Build configuration

- Trace selection is build configuration, not a source header that users edit
  manually.
- Generated configuration headers belong under `npc/build/` and are generated
  artifacts.
- Source files include one stable configuration interface, or the compiler
  force-includes the generated header.
- Derived settings such as instruction-state collection are generated from
  primary options rather than independently configured.

### Formatting

- Formatting must not alter existing copyright headers.
- Include sorting is disabled unless a later dedicated cleanup approves it.
- Historical files are not recursively reformatted.
- Formatting is limited to changed lines or newly created files.
- NEMU, NPC, and AM may use separate nearest-parent formatter configurations
  when their established styles differ.

## Accepted design

### Shared reference client

Introduce a NEMU-owned C++ `Riscv32DifftestReference` abstraction in
`nemu/include/difftest/reference.hpp` and
`nemu/tools/difftest-client/reference.cc` with these
responsibilities:

- acquire and release the dynamic-library handle;
- resolve all required symbols with their canonical types;
- validate the ABI version and state size;
- initialize the reference;
- copy memory to the reference;
- set and get canonical RV32 state;
- execute reference instructions;
- raise a reference interrupt.

The class must not know about `CPU_state`, `Vtop`, `npc_state`, NEMU logging, or
NPC mismatch reporting.

NPC compiles the NEMU-owned source into its host simulator. The implementation
source remains single-owned even though each consumer produces its own object
file.

### Shared protocol stages

The reference client also owns the identical protocol stages:

- reference initialization;
- image synchronization;
- initial DUT-state synchronization;
- one-step reference execution;
- reference-state retrieval;
- one-step execution followed by canonical state retrieval.

DUT state collection, comparison, diagnostics, stop policy, and NEMU's
skip/catch-up bookkeeping remain caller-owned. No virtual DUT hierarchy or
general session callback interface is introduced.

### NPC configuration profiles

Use checked-in human-editable profiles and a deterministic generator.

The profile format is TOML and is parsed through Python's standard-library
`tomllib`.

Initial configuration scope:

- instruction trace;
- function trace;
- memory trace;

The generator should:

- reject unknown keys and invalid value types;
- emit a single guarded C/C++ header;
- write atomically;
- avoid changing the output timestamp when content is unchanged;
- report the selected profile in the build output.

The Makefile accepts a named profile. Waveform generation, DiffTest enablement,
ISA selection, and other build options remain outside the initial generator.

### Formatter configuration

Evaluate the current NEMU-local candidate with:

- LLVM as the base style;
- two-space indentation;
- a 100-column limit;
- comment reflow disabled;
- include sorting disabled;
- macro-definition bodies skipped;
- `INSTPAT` treated as whitespace-sensitive.

The ignored NEMU-local formatter file is explicitly tracked without broadening
the existing ignore rules. NPC formatter configuration is deferred until its
current C++ host code has stabilized.

### C and C++ boundaries

- NEMU's DiffTest DUT source migrates from `.c` to `.cc`.
- Existing functions called by C translation units retain C linkage.
- NPC's DiffTest source uses a `.cc` suffix.
- A stable NPC configuration header includes the generated header explicitly;
  compiler-wide force inclusion is not used.

## Migration and rollback order

### 1. Record baselines

- Preserve or temporarily isolate unrelated worktree changes.
- Build NEMU's Spike DiffTest reference.
- Run the focused NEMU DiffTest regression.
- Build NPC and record the exact image and reference library used for its
  current DiffTest path.

No source behavior changes in this step.

### 2. Adopt the formatter configuration

- Review the NEMU-local candidate diff on representative C, C++, macro-heavy,
  and DiffTest files.
- Track the configuration without formatting historical files.
- Document changed-line formatting as the supported workflow.

Rollback removes only the formatter configuration.

### 3. Introduce generated NPC configuration

- Add one default profile and the generator.
- Generate the header under `npc/build/`.
- Route the existing trace macros through the generated interface.
- Preserve the current default behavior with every trace disabled.
- Remove the manually maintained fallback header only after all consumers use
  the generated interface.

Rollback restores the existing Make definitions and fallback header.

### 4. Migrate NPC to the canonical RV32 ABI

- Include the canonical RV32 state definition.
- Remove NPC's copied state layout, direction constants, and legacy symbol
  declarations.
- Add ABI version and state-size rejection before state transfer.
- Add an NPC-specific export adapter for the architectural state it currently
  implements.

Rollback returns NPC to its old reference library and caller as one unit.

### 5. Extract the shared reference client

- Introduce the C++ shared-library wrapper.
- Migrate NEMU without changing its step semantics.
- Validate NEMU before modifying NPC.
- Migrate NPC and remove its copied loader and symbol-resolution code.

Each caller migration is a separate commit and rollback boundary.

### 6. Remove obsolete protocol copies

- Confirm that both callers use the shared initialization and one-step
  operations.
- Remove copied symbol tables, dynamic loading, and direction dispatch.
- Preserve each DUT's adapter, diagnostics, skip behavior, and stop policy.

## Risks and failure modes

- A generated header can become stale if Make dependencies are incomplete.
- Profile changes can silently retain old objects if output timestamps or build
  prerequisites are incorrect.
- Different clang-format versions can produce different changed-line output.
- Full-file formatting can create large unrelated diffs in macro-heavy
  instruction code.
- Moving NEMU's DiffTest caller to C++ can accidentally change C linkage.
- A shared client can become coupled to NEMU assertions, logging, or private
  types if its boundary is not kept narrow.
- A premature shared session can hide meaningful NEMU/NPC behavioral
  differences behind callbacks.
- NPC cannot validate architectural state that is not exposed or implemented
  by its RTL; the adapter and comparison policy must state this limitation.

## Acceptance criteria

### Formatting

- Existing copyright headers are byte-for-byte unchanged.
- Formatting a changed ABI declaration produces no unrelated file-wide diff.
- `INSTPAT` and multi-line macro bodies retain their intended structure.

### NPC configuration

- A default profile reproduces the current trace-disabled build.
- Each trace option can be enabled without editing a source or tracked header.
- Invalid and unknown configuration keys fail before compilation.
- Re-running the generator with unchanged input does not update its output.

### DiffTest

- NEMU and NPC use one canonical RV32 state definition and typed symbol
  contract.
- Missing, stale, or size-incompatible reference libraries fail during
  initialization with an explicit diagnostic.
- NEMU and NPC contain no copied `dlopen`/`dlsym` protocol sequence after both
  migrations.
- DUT-specific state collection and mismatch behavior remain independently
  reviewable.

## Validation commands

NEMU reference and focused Spike DiffTest:

```sh
make -C nemu/tools/spike-diff GUEST_ISA=riscv32
make -C am-kernels/tests/cpu-tests ARCH=riscv32-nemu -j 1 run ALL=dummy
```

NEMU full DiffTest regression:

```sh
make -C am-kernels/tests/cpu-tests ARCH=riscv32-nemu -j 1 run
```

NPC build and smoke run:

```sh
make -C npc sim
make -C npc run
```

Trace-profile validation must record the selected profile, generated macros,
build command, image, reference model, expected trace output, and whether a
timeout is intentional.
