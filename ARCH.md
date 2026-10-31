# Architecture

This document fixes module boundaries and interfaces so that later work (icache, branch prediction,
SoC devices, formal check) plugs into existing seams instead of reshaping the core.

## Top level

```
ysyx_00000000 (SoC-facing top, cpu-interface.md ports)
 ├─ ysyx_00000000_Core        pipeline; only two simple memory ports (imem, dmem)
 ├─ ysyx_00000000_ICache      imem slave  -> AXI4 read master (refill / uncached fetch)
 ├─ ysyx_00000000_DmemXbar    dmem slave  -> CLINT | LSU AXI bridge (address decode)
 │   ├─ ysyx_00000000_CLINT   mtime, 1-cycle simple slave
 │   └─ ysyx_00000000_LSUAXI  dmem slave  -> AXI4 master (single beat, narrow transfers)
 └─ ysyx_00000000_AXIArbiter  2 AXI4 masters -> io_master (one transaction at a time)
```

`Core` never sees AXI. This keeps the formal harness simple: it drives `imem`/`dmem` directly with
nondeterministic latency and data, and compares retirements against a single-cycle reference model.

## Pipeline

Five stages, each owning its *input* register (valid + payload struct), connected by valid/ready:

```
IFU --if2id--> IDU --id2ex--> EXU --ex2mem--> MEU --mem2wb--> WBU
```

* **IFU**: PC register, branch predictor lookup at request time, at most one in-flight `imem` request.
  On a flush with a request in flight the response is dropped when it arrives (AXI cannot be cancelled).
* **IDU**: decode, regfile read, forwarding (EX > MEM > WB, youngest wins), stall on a
  not-yet-available producer (load or CSR result in EX/MEM).
* **EXU**: ALU (also does branch compare), target adder, resolves every instruction's actual next PC
  and compares it with the predicted one carried from IF. Mismatch → redirect on EX fire. Misaligned
  targets become an exception on the jump itself.
* **MEU** (memory/commit): the single point with irreversible side effects: dmem access, CSR read/write,
  trap entry, `mret`, `fence.i`. An instruction in MEU is never speculative (all older branches have
  resolved in EX, all older instructions are in WB and cannot trap). Redirect on MEU fire.
* **WBU**: regfile write and the retirement record (for DiffTest, counters, ebreak).

Flush rules: an EX redirect clears IFU in-flight, IF/ID and ID/EX registers; an MEU redirect additionally
blocks the EX→MEU transfer. MEU redirect has priority. `fence.i` is a MEU redirect to `pc+4` plus an
icache invalidate, so stale younger instructions in the pipeline are flushed by the same mechanism.

Precise exceptions: exceptions found in IF/ID/EX/MEU travel with the instruction (`exc`, `cause`) and are
taken only in MEU.

## Memory ports

`imem`: `req(valid, ready, addr)`, `resp(valid, ready, inst, err)`; in order; the slave holds the
response until accepted. `fencei` pulses invalidate the cache.

`dmem`: `req(valid, ready, addr, wen, size, wdata, wstrb)` (data already byte-lane aligned),
`resp(valid, rdata, err)` (raw 32-bit lane data); one outstanding request; the core is always ready.

## CSRs

mstatus (MIE, MPIE; MPP hardwired to M), mtvec, mepc, mcause, mvendorid, marchid. Anything else is an
illegal instruction.

## Build and test

All commands run from `work/` after `source ../env.sh`.

* `make sim` builds the Verilator model (`TRACE=1` adds FST waveforms, `--wave FILE` at run time).
* `make run-img IMG=x.bin [BOOT=mrom] [DIFFTEST=0]` runs a raw image.
* `make test-cpu` runs every am-kernels cpu-test on ysyxSoC with DiffTest (`wrong` must fail).
* AM programs: `make ARCH=riscv32e-ysyxsoc run` in any am-kernels directory (`YSYX_WORK` points
  the AM run rule at this directory).
* `make syn [SYN_FREQ=MHz]` synthesizes the core on nangate45 and runs STA (`build/syn/`).
* yosys cannot parse package imports in module headers, so synthesis and formal flows convert
  the RTL with `sv2v -DSYNTHESIS` first.

## Simulation

`sim/` is a Verilator C++ harness around `ysyxSoCFull`. A sim-only DPI hook in WBU reports every
retirement; the harness keeps a shadow GPR file, ends on ebreak, and runs DiffTest against Spike
(`processor_t` on a custom `simif_t` that models MROM/SRAM/flash/PSRAM/SDRAM). Retirements touching
devices are marked skip and the REF state is synced from the DUT.

## SoC boot and devices

* Reset PC is `0x30000000` (XIP flash). The FSBL in AM `start.S` runs in place and copies the
  SSBL into SRAM (`0x0f000000`); the SSBL copies the image into `YSYXSOC_RAM` (`sdram` by default,
  or `psram`/`sram`) and zeroes bss. The stack stays in SRAM. The linker script uses no MEMORY
  regions so sections inserted by programs keep the image contiguous in flash and RAM.
* ysyxSoC device RTL lives in `deps/ysyxSoC/perip`: XIP flash through the SPI master, PSRAM and
  SDRAM chip models, GPIO, PS/2, VGA and the bitrev SPI slave. SDRAM is extended to two ranks of
  two x16 chips (32-bit words, 128 MiB) in the Chisel sources; `make sim` regenerates
  `ysyxSoCFull.v` when they change.
* The batch harness models the board: `--uart-input/--uart-after/--uart-exit` (serial line),
  `--switches`, `--trace-gpio`, `--ps2 HEX,...` with `--ps2-at`, and `--vga-dump FILE.ppm`.
  `make nvboard` / `make run-nvboard IMG=...` build and run the interactive NVBoard version.
* `make test-mem [MEM_KIB=N]` runs mem-test over PSRAM and SDRAM (the full sweep takes hours);
  `make test-rtthread` boots RT-Thread and runs a command typed over UART.

## Performance and calibration

* Sim-only counters (`--perf`): retired instructions by class with their cycles, fetch latency,
  load/store latency by region, icache hits, misses and miss penalty. Retired instructions carry
  a class tag that synthesis removes as unused; handshakes reach the harness through SimHook.
* ysyxSoC's APB and AXI delayers stretch device latency by r = CPU_MHZ / 100 (8-bit fixed point),
  so a transaction or burst beat the device returns k cycles after t0 arrives k * r cycles after it.
  `CPU_MHZ` (Makefile, default 813 = synthesized fmax) and AM's `MTIME_PER_US` must agree.
* SDRAM uses the AXI controller so icache refills are single INCR bursts.
* icache: 16 B blocks, 4 sets, 2 ways, LRU, chosen with cachesim (`tools/`, data in `dse/icache.md`).
  `--itrace FILE[.zst]` writes the fetch trace; cachesim reproduces the RTL's hit count exactly.
  Shapes can be overridden with `SIM_DEFINES`/`SYN_DEFINES` (`ICACHE_BLOCK_BYTES`, `ICACHE_SETS`,
  `ICACHE_WAYS`).
* `make microbench [MB_SIZE=test|train]` runs microbench with counters.
* Branch prediction: 8-entry BTB with 2-bit counters, chosen with branchsim (`--btrace`, data in
  `dse/bpu.md`). `make test-fencei[-neg]` and `make -C formal icache` cover fence.i and the icache.
