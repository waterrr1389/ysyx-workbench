# Report

Pipelined RV32E + Zicsr + Zifencei core `ysyx_00000000` on ysyxSoC. Architecture and module
boundaries: `ARCH.md`. Design-space data: `dse/icache.md`, `dse/bpu.md`.

All commands run from `work/` after `source ../env.sh`.

## Results

| | value |
|---|---|
| Area (core without ysyxSoC, nangate45) | **23623 um^2** (limit 25000) |
| Maximum frequency | **813 MHz** |
| microbench train, cycles | 1,667,679,651 |
| microbench train, instructions | 192,013,487 |
| IPC | **0.1151** |
| microbench "Total time" | **2038.6 ms** (Scored time 1678.3 ms) |

Device latency is calibrated to the 813 MHz core: ysyxSoC's APB and AXI delayers stretch every device
answer by r = 813 / 100 (`CPU_MHZ` in the Makefile, `MTIME_PER_US` in AM). Times are therefore real
time at 813 MHz.

Effect of the stage-4 changes on microbench train (stage 3: same icache, static not-taken prediction,
715 MHz):

| | stage 3 | final |
|---|---|---|
| fmax | 715 MHz | 813 MHz |
| cycles | 1,739,757,259 | 1,667,679,651 (at a larger r) |
| fetch requests | 276,312,582 | 220,437,839 |
| branch mispredictions (branchsim) | 42.5 M | 14.4 M |
| Total time | 2420.4 ms | 2038.6 ms (-15.8%) |

## Acceptance items

| # | item | command | status |
|---|---|---|---|
| 1 | cpu-tests with DiffTest on ysyxSoC | `make test-cpu` | pass: all 35 (`wrong` fails as intended) |
| 2 | PSRAM and SDRAM mem-test | `make test-mem` (whole 4 MiB PSRAM and 128 MiB SDRAM; hours) or `make test-mem MEM_KIB=8` | pass |
| 3 | microbench on ysyxSoC | `make microbench` (`MB_SIZE=test\|train`) | pass: cycles and Total time above |
| 4 | RT-Thread with a shell command typed over UART | `make test-rtthread` | pass |
| 5 | fence.i self-modifying code | `make test-fencei`; `make test-fencei-neg` builds the core without the pipeline flush (`FENCEI_NO_FLUSH`) and without the icache invalidation (`FENCEI_NO_INVALIDATE`) | pass; both variants fail |
| 6 | synthesis on nangate45 | `make syn SYN_FREQ=900` (runs `make -C $YOSYS_STA_HOME sta PDK=nangate45 ...` on the sv2v output) | 23623 um^2, 813 MHz |

Formal check: `make -C formal icache` proves (abc pdr, unbounded) that the icache answers every
request with the word an uncached memory holds, under arbitrary bus stalls, and that no request after a
fence.i sees stale data; a cover task shows that case is reachable.

## Design decisions

**Pipeline.** Five stages with valid/ready handshakes and forwarding (EX > MEM > WB). MEU is the single
commit point: memory access, CSRs, traps, `mret` and `fence.i` all happen there, so exceptions are
precise without extra machinery (an exception travels with its instruction and is taken in MEU).
fence.i is an MEU redirect to pc + 4 plus an icache invalidate, flushing younger instructions with
the same mechanism as a trap.

**icache** (`dse/icache.md`). cachesim replays the fetch trace of microbench train and reproduces the
RTL's hit count exactly. Miss penalty per block size was measured in the calibrated SoC. Choice: 16 B
blocks, 4 sets, 2 ways, LRU (128 B):
- the lowest total miss time among shapes that fit the area limit;
- 256 B shapes take the core to about 29000 um^2;
- random replacement saves 6% of miss time (under 1% of run time) and would make cachesim no longer an
  exact reference;
- padding the program in RAM gave no gain.

**Branch prediction** (`dse/bpu.md`). branchsim replays retired branches and models a fetch-stage
predictor, which needs a BTB hit to predict taken. Choice: an 8-entry direct-mapped BTB with a 2-bit
counter per entry, keeping PC bits below bit 16 (code lies within 64 KiB). On microbench train it
mispredicts 14.35 M times against 42.52 M for not taken (backward-taken: 18.75 M). A full-width entry
costs about 230 um^2; narrowing tags and targets to 16 bits made 8 entries fit with no loss of
accuracy.

**Frequency.** With the BTB, fmax first fell to 677 MHz. The critical path was EXU's misprediction
check: branch compare, then a 32-bit compare of the actual next PC with the predicted one. Computing
the target and fall-through compares in parallel, with the branch condition only selecting between
them, raised fmax to 813 MHz.

**Memory latency.** SDRAM uses the AXI controller so icache refills are single bursts; the AXI delayer
calibrates each beat. Loads remain the largest cost (SDRAM loads average 63 cycles); a dcache was not
added because the remaining area (about 1400 um^2) cannot hold one.

## Checkpoints

Status of each task box in the B1–B5 handout pages. B3 has no programming content.

### B1

| task | status |
|---|---|
| Evaluate the single-cycle NPC's frequency and performance | skipped: the core was pipelined from the start; no single-cycle version exists |
| SimpleBus IFU / LSU, valid-only SimpleBus, testing SimpleBus, full-handshake SimpleBus | done in a different form: the core's imem/dmem ports are full valid/ready interfaces |
| Avoid handshake deadlock and livelock | done: valid never depends on ready; checked by the formal harness for the icache |
| AXI4-Lite IFU/LSU interfaces, AXI4-Lite arbiter | done as full AXI4 (bursts for refills), as ysyxSoC requires |
| Evaluate frequency and performance | done (Results) |
| AXI4-Lite UART | skipped: ysyxSoC's UART16550 is used |
| AXI4-Lite CLINT | done in a different form: CLINT sits on the core's dmem port, answering in one cycle |

### B2

| task | status |
|---|---|
| Get, generate and integrate ysyxSoC; MROM access; first character; output without newline | done |
| AM runtime for ysyxSoC; DiffTest again; mem-test | done (Spike is the DiffTest reference) |
| Load the data segment with a bootloader; putch; UART init; poll the status register | done |
| Read flash; SPI bit-reversal slave; flash through SPI; load from flash; XIP; replace MROM with flash | done (`spi-test`, reset PC 0x30000000) |
| Student-ID CSR | done (mvendorid 0x79737978, marchid 0) |
| PSRAM model in SPI mode; microbench on ysyxSoC; full PSRAM test; programs in PSRAM | done |
| Access PSRAM with QPI | skipped: the model and controller use Quad IO commands (EBh/38h) in SPI mode, not QPI |
| RT-Thread in PSRAM | done (`YSYXSOC_RAM=psram`) |
| Two-stage bootloader | done (FSBL in flash, SSBL in SRAM) |
| SDRAM model; full SDRAM test; programs in SDRAM; 32-bit data width; word extension | done (two ranks, 128 MiB) |
| LED chase; switches; student ID on 7-segment | done (`gpio-test`) |
| UART TX on NVBoard; UART input on NVBoard; typing into RT-Thread | done (NVBoard and batch harness) |
| Keyboard from NVBoard; VGA to NVBoard; a game on NVBoard | done (fceux-am Mario) |
| Run other AM programs from RT-Thread | done (`am_hello`) |
| ChipLink | skipped: out of scope (SPEC) |

### B4

| task | status |
|---|---|
| Measure IPC; performance counters (1) and (2); find bottlenecks | done (`--perf`) |
| Calibrate memory latency; highest synthesis frequency; re-find bottlenecks; evaluate NPC | done |
| Faster functional testing | done: r = 1 builds for correctness, parallel cpu-tests |
| icache; cacheable address space | done: every fetchable region is cached |
| Estimate the ideal gain of a dcache | skipped: no area for a dcache; load cost is in the counters |
| AMAT; cachesim; DSE with cachesim | done (`dse/icache.md`) |
| Larger blocks (1) and (2); AXI SDRAM; burst refill; AXI delayer; burst performance; quick miss penalty | done |
| Optimize the program layout | done: padding evaluated, no gain |
| icache DSE | done |
| dcache cost-effectiveness | skipped: see above |
| Reproduce the coherence problem; fence.i | done (`make test-fencei-neg`) |
| Reproduce it in the bootloader | skipped: reproduced with the self-modifying-code test instead |
| fence.i in the bootloader | done: `start.S` executes fence.i after each copy |
| Formal check of the icache | done (`formal/`) |

### B5

| task | status |
|---|---|
| Ideal gain of a dcache; dcache with cachesim | skipped: no area for a dcache |
| Ideal gain of better compute efficiency | skipped: not measured separately |
| Simple pipeline; pipeline with exceptions | done |
| Evaluate the simple pipeline; locate bottlenecks | done (counters) |
| Gain of a pipelined icache | done in the design: a hit answers in the cycle after the request, one instruction per cycle |
| Ideal gain of forwarding; forwarding | forwarding done; no before/after measurement (the core had forwarding from the start) |
| Gain of removing control-hazard stalls; importance of branch prediction; branchsim; gain of correct speculation | done (`dse/bpu.md`) |
| Optimize the pipeline | done: BTB predictor, misprediction check restructured for 813 MHz |
| Design counterexamples | done in a different form: the formal harness drives arbitrary stalls; cpu-tests, RT-Thread and the fence.i tests run under DiffTest |
| fence.i in the pipeline | done (`make test-fencei`, `make test-fencei-neg`) |
