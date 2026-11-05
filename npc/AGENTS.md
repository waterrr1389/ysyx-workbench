# Repository Guidelines

## Project Structure & Module Organization
`vsrc/` holds the hand-written SystemVerilog RTL, a multi-cycle core with a valid/ready handshake between stages. `top.sv` is the top module for the Verilator flow and `npc_pkg.sv` holds the shared types and constants; `IFU`, `IDU`, `EXU`, `LSU` and `WBU` are the pipeline stages run one instruction at a time, `RegFile` is the register file, and `WBU` is the single commit point (register write, CSR updates, traps, next PC). `IFU` and `LSU` are AXI4 masters; `Arbiter` picks one of them and `Xbar` routes its request by address to `SRAM` (`0x8000_0000`, 32MB) or the write-only `UART` (`0x1000_0000`), answering anything else, and UART reads, with DECERR; reads of the RTC (`0xa000_0048`, 8 bytes) also go to the SRAM port and `pmem_read` returns host time. DPI-C crosses into C in four places: `SRAM` imports `pmem_read`/`pmem_write`, `UART` imports `uart_putc`, `WBU` imports `npc_trap`/`npc_abort_at`, and `RegFile` exports `get_gpr`. `csrc/` is the Verilator harness: `sim_main.cpp` owns clock, reset, tracing and argument parsing, `dpi-c.cpp` implements the DPI-C hooks, `pmem.cpp` backs physical memory, `sdb.c` is the debugger, `difftest/` holds the reference comparison, and `trace/` holds the instruction, function and memory tracers. Headers live in `include/<module>/` (`base`, `sim`, `difftest`, `trace`) and are included as `"sim/pmem.h"`. `formal/` holds the AXI4 formal checks of the memory path. The model is built by Meson (`meson.build`); simulation options live in `meson.options` and become `npc_config.h` in the build directory. Treat `../build-npc*/` and `waveform.fst` as generated output only.

## Build, Test, and Development Commands
- `make sim`: build the Verilator model into `../build-npc/Vtop`.
- `make run IMG=<image.bin> ARGS="-b -e <image.elf>"`: run the model; `-b` is batch mode and `-e` loads ELF symbols. Always pass `IMG=`: the default `./dummy.bin` does not exist. Running through AM with `ARCH=riscv32i-npc` fills these in.
- `meson setup ../build-npc-diff . -Ddifftest=true` then `make sim BUILD_DIR=$PWD/../build-npc-diff`: another configuration in its own build directory; options are listed in `meson.options`.
- `make wave`: open `waveform.fst` in GTKWave.
- `make gdb`: debug the model under GDB.
- `make clean`: remove the build directory.
- `make -C formal`: run the AXI4 formal checks (`prove` and `cover`) on the bus (`Arbiter`, `Xbar`, `SRAM`, `UART` together), `IFU` and `LSU`. `make -C formal <job>` runs one of `bus|ifu|lsu`; add `TASKS=prove` or `TASKS=cover` to pick one task. Needs `sby`, `yosys`, `yices` and `sv2v`.

`NPC_HOME` and `NEMU_HOME` must be set, which `init.sh` at the workspace root arranges. The `tracer-sim-rtl` target in `meson.build` (a `git_commit` after each model build) is course grading tooling; leave it in place.

## Coding Style & Naming Conventions
Verilog keeps the style already used in `vsrc/`: module and file names that match the function (`IDU.sv`, `EXU.sv`, `top.sv`), explicit signal widths, and `top` as the Verilator top module. C/C++ keeps small functions and warning-free builds. Beyond that, follow the workspace root `../AGENTS.md`.

## Chisel Conventions
These apply to Chisel sources added under `npc/`. Chisel breaks APIs between releases far more often than Verilog does, and knowledge of current Chisel is thin compared with mainstream languages, so the version and the API surface are pinned deliberately rather than tracked.

### Versions and API surface
- Pin the Chisel version in the build file. Do not upgrade opportunistically; upgrade only when a needed feature requires it, and re-run the RTL tests in the same change.
- Stay inside this subset: `Module`, `RawModule` (for purely combinational blocks, which then carry no clock or reset ports), `IO`, `Wire`, `Reg`, `RegInit`, `when`/`elsewhen`/`otherwise`, `switch`/`is`, `Mux`, `Cat`, `VecInit`, `ChiselEnum`, plus the handshake pieces of `chisel3.util` that have stayed stable since Chisel 3: `Bundle`, `Flipped`, `Decoupled`, `.fire`, `<>`, `Queue`, the table helpers `MuxLookup`, `ListLookup`, `BitPat` for decoding, and the bit helpers `Fill`, `Reverse`, `MuxCase`. Methods on `UInt`/`SInt` from `chisel3._` itself (`asSInt`, `asUInt`, `pad`, `orR`, `andR`, `xorR`, `asTypeOf`) need no listing. Plain Scala functions and collections (`Seq.tabulate`, `map`) that generate hardware are fine. Do not reach for experimental APIs. The single sanctioned exception is `chisel3.util.circt.dpi`, which is how the design reaches the C memory model.
- Every register uses `RegInit`. A bare `Reg` has no reset value and reads as X under Verilator.
- `import chisel3._` goes first, then a blank line, then the remaining imports alphabetically. No wildcard imports other than `chisel3._`; name what is used from `chisel3.util`, as in `import chisel3.util.{Decoupled, Queue}`.
- One module per file, and the filename is the name of the top-level class it holds.

### Naming
- `lowerCamelCase` for values and methods, `UpperCamelCase` for classes, objects and constants.
- No `snake_case`. The compiler inserts underscores when it flattens aggregates, so `msgRec` beside `msg.valid` and `msg.addr` yields `msg_valid`, `msg_addr`, `msgRec`; naming it `msg_rec` would read as a fourth field of `msg` in the waveform.
- Acronyms are treated as words: `findGcd`, `stateForFsm`, `fifoGenerator`, not `findGCD`, `stateForFSM`, `FIFOGenerator`.

### Combinational logic and state machines
- Last connect wins. Write defaults first, then override inside `when` blocks:

  ```scala
  req := false.B
  when (ready) { req := true.B }
  ```

- Combinational outputs must be assigned on every path or elaboration fails. That check is intentional; do not work around it.
- State machines use `ChiselEnum` with `switch`/`is`, written as one block that assigns `state` directly. There is no separate `next_state`; last connect supplies the priority order.

### Top-level IO
Declare top-level ports flat, as in `val led = IO(Output(UInt(16.W)))`, not inside an `io` Bundle. A Bundle named `io` flattens to `io_led` and similar, and every such name then has to be repeated in the constraint file, the C++ harness and the Makefile. This applies only to the module the harness or the SoC instantiates; interfaces between internal modules should be Bundles, with `Decoupled` for anything that handshakes.

### Fitting the existing Verilator flow
- Chisel names the clock and reset ports `clock` and `reset`. `vsrc/top.v` names them `clk` and `reset`, and `csrc/sim_main.cpp` drives `top->clk`, so either drive `clock` from the harness or keep a thin wrapper module named `top` that renames the ports.
- `meson.build` lists every RTL source explicitly in `vsrcs`, with `npc_pkg.sv` first; a new or generated `.sv` that is not added there is silently left out of the model. Harness sources go in `csrcs` and headers in `headers`, or edits to them do not rebuild the model.
- `--top-module top` only holds while a module named `top` stays the top, which is another reason to keep the wrapper.
- Memory access goes through `import "DPI-C" pmem_read/pmem_write` in `vsrc/SRAM.v`. Chisel 7 expresses the same calls with `chisel3.util.circt.dpi`: `RawUnclockedNonVoidFunctionCall` for the combinational read and `RawClockedVoidFunctionCall` for the write. Both lower to `import "DPI-C"`, so `csrc/dpi-c.cpp` is reused unchanged. These intrinsics are absent from Chisel 6.x, which is a concrete reason to stay on 7.x. A BlackBox carrying an inline `import "DPI-C"`, or plain memory ports driven from C++, remain valid alternatives.
- Replacing existing RTL rather than adding an isolated block is a cross-module change; write the specification under `../development/` and get it approved first, as the workspace root `../AGENTS.md` requires.

### Formatting
`.scalafmt.conf` in this directory holds the settings (`maxColumn = 120`, `preset = defaultWithAlign`, `rewrite.imports.sort = scalastyle`, `rewrite.trailingCommas.style = never`) and pins the formatter version. Run it before committing; under Mill that is `./mill <module>.reformat`, with `./mill <module>.checkFormat` for CI. Do not enable `rewrite.imports.expand`: it would expand `import chisel3._` and break the import convention above.

## Testing Guidelines
Validation is run-oriented: for an RTL change run `make sim`, then a program through AM (`make -C ../am-kernels/tests/cpu-tests ARCH=riscv32i-npc run ALL=dummy`), and inspect the waveform with `make wave` when behavior changes.

Changes to `SRAM.sv`, `Arbiter.sv`, `Xbar.sv`, `UART.sv`, `IFU.sv`, `LSU.sv` or their bus ports also need `make -C formal` to pass. The checks live in `formal/`:
- `axi_props.sv` holds this project's own AXI4 protocol properties for one link (single-beat transfers, at most one transaction in flight). Each check module instantiates it per link, asserting what the design under test drives and assuming what its environment drives. Data values are not checked, so DiffTest still owns data correctness.
- `bus_check.sv` puts `Arbiter`, `Xbar`, `SRAM` and `UART` under two unconstrained masters that obey the protocol; `ifu_check.sv` and `lsu_check.sv` check `IFU` and `LSU` against any protocol-abiding slave.
- The Makefile runs `sv2v` over the `npc_pkg.sv`, `axi_props.sv` and the sources of one job into `formal/build/<job>.v`, because Yosys reads neither packages nor packed structs. It never edits `vsrc/`. If a check fails to parse after an RTL edit, fix the job's source list or the RTL's SystemVerilog subset, not the generated file.
- Each `.sby` has a `cover` task. A cover that stops being reached means the assumptions have become too strong and the asserts may pass vacuously.
- A FAIL from `prove` comes with a counterexample trace under `build/<job>_prove/`; read it before touching the RTL or the assumptions. No FPGA board is used here, so NVBoard is the board substitute once it is wired into this Makefile. `NVBOARD_HOME/scripts/auto_pin_bind.py` reads only the `.nxdc` constraint file and the board pin table and never the HDL, so it works unchanged with generated Verilog; the signal names in the `.nxdc` must equal the top-level port names. Record the active `CONFIG`, the image used and whether any timeout was intentional when reporting results.

## Commit & Pull Request Guidelines
Recent history favors short, imperative commit messages, optionally prefixed (`fix:`, `refactor:`) and scoped by module or feature. Keep one logical change per commit. PRs should state the purpose, the affected module, the exact build and run commands used, and relevant output when behavior changes.
