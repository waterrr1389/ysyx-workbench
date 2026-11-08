# Repository Guidelines

## Project Structure & Module Organization
`vsrc/` holds the hand-written SystemVerilog RTL, a multi-cycle core with a valid/ready handshake between stages. `top.sv` is the top module for the Verilator flow and `npc_pkg.sv` holds the shared types and constants. `Core` is the processor: `IFU`, `IDU`, `EXU`, `LSU` and `WBU` are the pipeline stages run one instruction at a time, `RegFile` is the register file, and `WBU` is the single commit point (register write, CSR updates, traps, next PC). `IFU` and `LSU` are AXI4 masters; `Arbiter` picks one of them and `CoreXbar` keeps reads of the `CLINT` (a read-only 64-bit `mtime` at `0x0200_0000` that counts cycles) inside the core and sends every other access out on the core's single AXI4 master port. `top` adds the memory system around `Core`: `Xbar` routes by address to `SRAM` (`0x8000_0000`, 32MB) or the write-only `UART` (`0x1000_0000`), answering anything else, and UART reads, with DECERR. DPI-C external models are `SRAM` (`pmem_read`/`pmem_write`), `UART` (`uart_putc`), and `WBU` (`npc_trap`/`npc_abort_at`). `sim_observer.sv`, guarded by `NPC_SIM`, binds passive observers by module type and reports architectural snapshots only on reset release and after commits, and marks CLINT reads for DiffTest to skip (`npc_device_read`). `cpu_state.cpp` copies these reports for DiffTest, tracing and the debugger; the harness never queries an RTL scope or a debug port. `csrc/` is the Verilator harness: `sim_main.cpp` owns clock, reset, tracing and argument parsing, `dpi-c.cpp` implements the DPI-C hooks, `pmem.cpp` backs physical memory, `sdb.c` is the debugger, `difftest/` holds the reference comparison, and `trace/` holds the instruction, function and memory tracers. Headers live in `include/<module>/` (`base`, `sim`, `difftest`, `trace`) and are included as `"sim/pmem.h"`. `formal/` holds the AXI4 formal checks of the memory path. The model is built by Meson (`meson.build`); simulation options live in `meson.options` and become `npc_config.h` in the build directory. Treat `../build-npc*/` and `waveform.fst` as generated output only.

## Build, Test, and Development Commands
- `make sim`: build the Verilator model into `../build-npc/Vtop`.
- `make run IMG=<image.bin> ARGS="-b -e <image.elf>"`: run the model; `-b` is batch mode and `-e` loads ELF symbols. Always pass `IMG=`: the default `./dummy.bin` does not exist. Running through AM with `ARCH=riscv32i-npc` fills these in.
- `meson setup ../build-npc-diff . -Ddifftest=true` then `make sim BUILD_DIR=$PWD/../build-npc-diff`: another configuration in its own build directory; options are listed in `meson.options`.
- `make wave`: open `waveform.fst` in GTKWave.
- `python3 tests/snapshot.py ../build-npc/Vtop`: exercise reset, writeback, CSR and trap snapshots through sdb; add `--ftrace` for a build with ftrace enabled.
- `make gdb`: debug the model under GDB.
- `make clean`: remove the build directory.
- `make -C formal`: run the AXI4 formal checks (`prove` and `cover`) on the bus (`Arbiter`, `Xbar`, `SRAM`, `UART` together), `IFU` and `LSU`. `make -C formal <job>` runs one of `bus|ifu|lsu`; add `TASKS=prove` or `TASKS=cover` to pick one task. Needs `sby`, `yosys`, `yices` and `sv2v`.

`NPC_HOME` and `NEMU_HOME` must be set, which `init.sh` at the workspace root arranges. The `tracer-sim-rtl` target in `meson.build` (a `git_commit` after each model build) is course grading tooling; leave it in place.

## Coding Style & Naming Conventions
Verilog keeps the style already used in `vsrc/`: module and file names that match the function (`IDU.sv`, `EXU.sv`, `top.sv`), explicit signal widths, and `top` as the Verilator top module. C/C++ keeps small functions and warning-free builds. Beyond that, follow the workspace root `../AGENTS.md`.

## Testing Guidelines
Validation is run-oriented: for an RTL change run `make sim`, then a program through AM (`make -C ../am-kernels/tests/cpu-tests ARCH=riscv32i-npc run ALL=dummy`), and inspect the waveform with `make wave` when behavior changes.

Changes to `SRAM.sv`, `Arbiter.sv`, `Xbar.sv`, `UART.sv`, `IFU.sv`, `LSU.sv` or their bus ports also need `make -C formal` to pass. The checks live in `formal/`:
- `axi_props.sv` holds this project's own AXI4 protocol properties for one link (single-beat transfers, at most one transaction in flight). Each check module instantiates it per link, asserting what the design under test drives and assuming what its environment drives. Data values are not checked, so DiffTest still owns data correctness.
- `bus_check.sv` puts `Arbiter`, `Xbar`, `SRAM` and `UART` under two unconstrained masters that obey the protocol; `ifu_check.sv` and `lsu_check.sv` check `IFU` and `LSU` against any protocol-abiding slave.
- The Makefile runs `sv2v` over the `npc_pkg.sv`, `axi_props.sv` and the sources of one job into `formal/build/<job>.v`, because Yosys's built-in frontend cannot parse parts of the SystemVerilog used here, such as package imports in module headers and the `inside` operator. It never edits `vsrc/`. If a check fails to parse after an RTL edit, fix the job's source list or the RTL's SystemVerilog subset, not the generated file.
- Each `.sby` has a `cover` task. A cover that stops being reached means the assumptions have become too strong and the asserts may pass vacuously.
- A FAIL from `prove` comes with a counterexample trace under `build/<job>_prove/`; read it before touching the RTL or the assumptions. No FPGA board is used here, so NVBoard is the board substitute once it is wired into this Makefile. `NVBOARD_HOME/scripts/auto_pin_bind.py` reads only the `.nxdc` constraint file and the board pin table and never the HDL, so it works unchanged with generated Verilog; the signal names in the `.nxdc` must equal the top-level port names. Record the active `CONFIG`, the image used and whether any timeout was intentional when reporting results.

## Commit & Pull Request Guidelines
Keep one logical change per commit. PRs should state the purpose, the affected module, the exact build and run commands used, and relevant output when behavior changes.
