# Repository Guidelines

## Project Structure & Module Organization
This workspace is the YSYX multi-repo workbench. Core components are:
- `nemu/`: reference emulator (C), with monitor, ISA backends, and device models.
- `npc/`: Verilator-based RTL simulation project (`vsrc/` + `csrc/`).
- `abstract-machine/`: hardware abstraction layer used by AM programs.
- `am-kernels/`: benchmarks, kernels, and test programs built on AM.
- `nvboard/`: peripheral simulation support library.
- `riscv-tests-am/`, `riscv-arch-test-am/`: ISA test suites (submodules).
- `development/`: draft and accepted specifications for substantial cross-module changes.

Treat `build/` directories, `.config`, generated headers, and waveform/log outputs as generated artifacts.

## Build, Test, and Development Commands
- `bash init.sh <name>`: initialize/update expected subprojects and env vars (`nemu`, `abstract-machine`, `am-kernels`, `nvboard`, `npc`).
- `make -C nemu menuconfig`: open NEMU Kconfig.
- `make -C nemu riscv32-am_defconfig && make -C nemu -j$(nproc)`: load the checked-in RV32 preset and build NEMU.
- `make -C nemu run IMG=/path/to/image.bin ARGS="--log=build/nemu-log.txt --elf=/path/to/prog.elf"`: run with logs/ELF symbols.
- `make -C npc sim && make -C npc run`: build and run Verilator simulation.
- `make -C am-kernels/tests/cpu-tests ARCH=riscv32-nemu -j 1 run`: run the full CPU regression suite on NEMU.
- `make -C am-kernels/tests/cpu-tests ARCH=riscv32-nemu -j 1 run ALL=dummy`: run one CPU test; replace `dummy` with a filename stem from `tests/`.
- `make -C am-kernels/kernels/yield-os ARCH=riscv32-nemu`: build the `yield-os` image without running it.
- `make -C am-kernels/kernels/yield-os run ARCH=riscv32-nemu`: run `yield-os`; stop it manually because successful scheduling loops indefinitely.
- `make -C nemu/tools/spike-diff GUEST_ISA=riscv32`: build the RV32 Spike DiffTest shared library directly.
- `make -C <subproject> clean`: clean local build outputs.

CPU tests with DiffTest enabled must use `-j 1`. Omit `ALL` for the full suite;
set `ALL=<test>` to run one test.

## Coding Style & Naming Conventions
Follow style already used in each module (C/C++/Verilog conventions differ by subproject). Prefer:
- C/C++: small functions, clear names, warning-free builds (`-Wall -Werror` enabled in NEMU/NPC flows).
- Verilog: module/file names that match function (`IDU.v`, `EXU.v`, `top.v`), explicit signal widths.
- Keep filenames lowercase where existing code does so; avoid mixed naming styles within one directory.

## Adversarial Coding Habits
- After a module passes its tests, attack it once: construct counterexamples for off-by-one cycles, boundary addresses, and hazard timing, especially around forwarding, stall, cache FSM, and address mapping logic.
- Encode key invariants as assertions so bugs announce themselves; investigate every assertion failure or report, never silence it.
- For subtle logic, comments state why it must be this way and what breaks if changed, not just what it does.
- Never use absolute paths or toolchain-specific behavior; builds must work through the project's own scripts.

## AI Collaboration Style
This is a learning project: default to guiding over handing over answers.
- For debugging and conceptual questions, ask what the user has observed and tried first, then suggest what to verify next (signal, log, code path, experiment) rather than stating the fix.
- When the user offers a hypothesis, check it against evidence instead of replacing it; if it is wrong, show the evidence.
- Give direct answers and implementation for mechanical work (build scripts, tooling, boilerplate) or when the user explicitly asks to skip guidance.
- For every key claim, point to the manual, doc, or code location that settles it.

## Testing Guidelines
No single unified unit-test framework exists at workspace root. Validate by runnable targets:
- Emulator instruction changes: rebuild `nemu/`, run a focused CPU test with `ALL=<test>`, then run the full CPU suite.
- DiffTest adapter changes: build `nemu/tools/spike-diff`, run at least one focused CPU test with Spike DiffTest enabled, then run the full CPU suite.
- CTE or context-switch changes: build and run `yield-os`; continuous expected output is a successful non-terminating result, not a hung test.
- RTL changes: run `make -C npc sim run` and inspect waveform when behavior changes (`make -C npc wave`).
- Record the active `ARCH`, NEMU configuration, reference model, and whether a timeout was intentional when reporting results.
- Include exact commands used for verification in your PR description.

## Development Specifications
Use `development/` for substantial changes that cross module boundaries, alter an ABI, or introduce architectural state.

- Read `development/README.md` before creating or updating a specification.
- Keep confirmed decisions separate from proposals and open questions.
- Do not start implementation until the specification identifies scope, risks, migration order, rollback boundaries, and acceptance criteria, and the user has approved them.
- Update the specification when an implementation decision changes; do not leave the only record in conversation history.

## Commit & Pull Request Guidelines
Recent commits are short, imperative, and often scoped (for example `fix: ...`, `refactor: ...`, or concise module-specific Chinese messages). Keep one logical change per commit.

PRs should include:
- What changed and why.
- Affected modules (`nemu`, `npc`, `am-kernels`, etc.).
- Repro/build/test commands and key outputs.
- Linked issue/task ID when applicable.
