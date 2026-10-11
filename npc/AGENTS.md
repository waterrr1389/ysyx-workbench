# Repository Guidelines

## Project Structure & Module Organization
`vsrc/` holds the hand-written Verilog RTL. `top.v` is the top module for the Verilator flow; `EXU.v`, `IDU.v`, `IMME.v`, `OP1.v`, `OP2.v` are datapath units; `IFU.v` and `LSU.v` are AXI4-Lite masters; `Arbiter.sv` picks one of them and `Xbar.v` routes its request by address to `SRAM.v` (`0x8000_0000`, 32MB) or the write-only `UART.v` (`0xa000_03f8`), answering anything else, and UART reads, with DECERR; `alu_ops.vh` and `ctrl_defs.vh` are shared headers; `utils/` holds reusable helpers. DPI-C crosses into C in three places: `SRAM.v` imports `pmem_read`/`pmem_write`, `EXU.v` imports `npc_trap`, and `utils/Reg/RegisterFile.v` exports `get_gpr`. `csrc/` is the Verilator harness: `sim_main.cpp` owns clock, reset, tracing and argument parsing, `dpi-c.cpp` implements the DPI-C hooks, `pmem.cpp` backs physical memory, `sdb.c` is the debugger, `difftest/` holds the reference comparison. `trace/` holds the instruction, function and memory tracers. `formal/` holds the AXI4-Lite formal checks. Simulation configuration lives in `configs/*.toml` and is turned into `build/generated/<name>/npc_config.h` by `scripts/gen_config.py`. Treat `build/`, `waveform.fst` and generated config headers as generated output only.

## Build, Test, and Development Commands
- `make sim`: build the Verilator model into `build/Vtop`.
- `make run IMG=<image.bin> ARGS="-b -e <image.elf>"`: run the model; `-b` is batch mode and `-e` loads ELF symbols. Always pass `IMG=`: the default `./dummy.bin` does not exist. Running through AM with `ARCH=riscv32i-npc` fills these in.
- `CONFIG=configs/<name>.toml make sim`: select a configuration other than `configs/default.toml`.
- `make wave`: open `waveform.fst` in GTKWave.
- `make gdb`: debug `build/Vtop` under GDB.
- `make clean`: remove `build/`.
- `make -C formal`: run the AXI4-Lite formal checks (bmc, cover, prove) on `SRAM`, `Arbiter`, `Xbar`, `IFU`, `LSU` and `UART`. `make -C formal <job>` runs one of `sram|arbiter|xbar|ifu|lsu|uart`; add `TASKS=prove` to pick tasks. Needs `sby`, `yosys`, `yices` and `sv2v`.

`NPC_HOME` and `NEMU_HOME` must be set, which `init.sh` at the workspace root arranges. The `git_commit` call in the Makefile is course grading tooling; leave it in place.

## Coding Style & Naming Conventions
Verilog keeps the style already used in `vsrc/`: module and file names that match the function (`IDU.v`, `EXU.v`, `top.v`), explicit signal widths, and `top.v` as the Verilator top module. C/C++ keeps small functions and warning-free builds. Beyond that, follow the workspace root `../AGENTS.md`.

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
- The Makefile collects RTL with `find ./vsrc -name "*.v"`. Chisel emits `.sv`, which that glob drops without any error; widen the glob before generated files are added.
- `--top-module top` only holds while a module named `top` stays the top, which is another reason to keep the wrapper.
- Memory access goes through `import "DPI-C" pmem_read/pmem_write` in `vsrc/SRAM.v`. Chisel 7 expresses the same calls with `chisel3.util.circt.dpi`: `RawUnclockedNonVoidFunctionCall` for the combinational read and `RawClockedVoidFunctionCall` for the write. Both lower to `import "DPI-C"`, so `csrc/dpi-c.cpp` is reused unchanged. These intrinsics are absent from Chisel 6.x, which is a concrete reason to stay on 7.x. A BlackBox carrying an inline `import "DPI-C"`, or plain memory ports driven from C++, remain valid alternatives.
- Replacing existing RTL rather than adding an isolated block is a cross-module change; write the specification under `../development/` and get it approved first, as the workspace root `../AGENTS.md` requires.

### Formatting
`.scalafmt.conf` in this directory holds the settings (`maxColumn = 120`, `preset = defaultWithAlign`, `rewrite.imports.sort = scalastyle`, `rewrite.trailingCommas.style = never`) and pins the formatter version. Run it before committing; under Mill that is `./mill <module>.reformat`, with `./mill <module>.checkFormat` for CI. Do not enable `rewrite.imports.expand`: it would expand `import chisel3._` and break the import convention above.

## Testing Guidelines
Validation is run-oriented: for an RTL change run `make sim`, then a program through AM (`make -C ../am-kernels/tests/cpu-tests ARCH=riscv32i-npc run ALL=dummy`), and inspect the waveform with `make wave` when behavior changes.

Changes to `SRAM.v`, `Arbiter.sv`, `Xbar.v`, `UART.v`, `IFU.v`, `LSU.v` or their bus ports also need `make -C formal` to pass. The checks live in `formal/`:
- `*_axil.sv` wraps one module with ZipCPU's `faxil_slave`/`faxil_master` from `formal/vendor/` (kept unmodified, pinned to wb2axip `2e8d3bc`). They cover AXI4-Lite handshake rules, plus the Xbar address ranges; data and strobes are not checked, so DiffTest still owns data correctness.
- The Makefile adapts copies under `formal/build/`, never `vsrc/`: DPI-C is cut out of `SRAM.v`, `else $fatal` is dropped from immediate assertions, `Arbiter.sv` goes through `sv2v`, and the Arbiter and Xbar copies gain `f_*` ports exporting internal state, because Yosys cannot resolve hierarchical references. If a check fails to parse after an RTL edit, fix that adaptation rather than the RTL.
- The harnesses chain contracts: `sram_axil` assumes the SRAM never sees a read and a write at once and `uart_axil` assumes the UART never sees a read; `xbar_axil` proves both while assuming one transaction at a time from its master; `arbiter_axil` proves that while assuming each of IFU and LSU issues nothing new until its previous transaction completes; `ifu_axil`/`lsu_axil` prove that. Weakening an assumption means proving it on the other side.
- Every harness also carries reset-gated covers. A cover that stops being reached means the assumptions have become too strong and the asserts may pass vacuously.
- `prove` returning UNKNOWN is an induction failure, usually a missing invariant in the harness, not a design bug; read `build/<job>_prove/engine_0/trace_induct.vcd`. A FAIL from `bmc` is a real counterexample reachable from reset. No FPGA board is used here, so NVBoard is the board substitute once it is wired into this Makefile. `NVBOARD_HOME/scripts/auto_pin_bind.py` reads only the `.nxdc` constraint file and the board pin table and never the HDL, so it works unchanged with generated Verilog; the signal names in the `.nxdc` must equal the top-level port names. Record the active `CONFIG`, the image used and whether any timeout was intentional when reporting results.

## Commit & Pull Request Guidelines
Recent history favors short, imperative commit messages, optionally prefixed (`fix:`, `refactor:`) and scoped by module or feature. Keep one logical change per commit. PRs should state the purpose, the affected module, the exact build and run commands used, and relevant output when behavior changes.
