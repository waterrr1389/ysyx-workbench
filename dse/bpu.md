# Branch predictor design space exploration

Trace: retired branches and jumps of microbench train (52,506,768 conditional branches, 3,954,760
jumps), from `--btrace`; model: `tools/branchsim.cpp`. The predictor only sees the fetch PC, so a
taken prediction needs a BTB hit. Only taken outcomes allocate an entry. SPAN_W: tags and targets keep
PC bits below it (32 = full width); microbench code lies within 64 KiB, so 16 loses almost nothing.

## Mispredictions (branchsim, microbench train)

| policy | entries | SPAN_W | mispredictions | per 1000 instructions |
|---|---|---|---|---|
| bimod | 2 | 32 | 31837215 | 165.8 |
| bimod | 2 | 16 | 31837216 | 165.8 |
| bimod | 2 | 14 | 31857966 | 165.9 |
| bimod | 4 | 32 | 31205839 | 162.5 |
| bimod | 4 | 16 | 31205840 | 162.5 |
| bimod | 4 | 14 | 31317991 | 163.1 |
| bimod | 8 | 32 | 14350764 | 74.7 |
| bimod | 8 | 16 | 14350764 | 74.7 |
| bimod | 8 | 14 | 15305904 | 79.7 |
| bimod | 16 | 32 | 12025216 | 62.6 |
| bimod | 16 | 16 | 12025216 | 62.6 |
| bimod | 16 | 14 | 13810270 | 71.9 |
| bimod | 32 | 32 | 11338724 | 59.1 |
| bimod | 32 | 16 | 11338724 | 59.1 |
| bimod | 32 | 14 | 13163822 | 68.6 |
| btb | 2 | 32 | 31778608 | 165.5 |
| btb | 2 | 16 | 31786803 | 165.5 |
| btb | 2 | 14 | 31807553 | 165.7 |
| btb | 4 | 32 | 31258597 | 162.8 |
| btb | 4 | 16 | 31266792 | 162.8 |
| btb | 4 | 14 | 31381446 | 163.4 |
| btb | 8 | 32 | 14704743 | 76.6 |
| btb | 8 | 16 | 14712937 | 76.6 |
| btb | 8 | 14 | 15670203 | 81.6 |
| btb | 16 | 32 | 12731818 | 66.3 |
| btb | 16 | 16 | 12740012 | 66.3 |
| btb | 16 | 14 | 14528855 | 75.7 |
| btb | 32 | 32 | 12255483 | 63.8 |
| btb | 32 | 16 | 12263677 | 63.9 |
| btb | 32 | 14 | 14093014 | 73.4 |
| btfn | 2 | 32 | 31937547 | 166.3 |
| btfn | 2 | 16 | 31937547 | 166.3 |
| btfn | 2 | 14 | 31958149 | 166.4 |
| btfn | 4 | 32 | 31436923 | 163.7 |
| btfn | 4 | 16 | 31436923 | 163.7 |
| btfn | 4 | 14 | 31549101 | 164.3 |
| btfn | 8 | 32 | 18746026 | 97.6 |
| btfn | 8 | 16 | 18746025 | 97.6 |
| btfn | 8 | 14 | 19695669 | 102.6 |
| btfn | 16 | 32 | 16733473 | 87.1 |
| btfn | 16 | 16 | 16733472 | 87.1 |
| btfn | 16 | 14 | 18506010 | 96.4 |
| btfn | 32 | 32 | 16098876 | 83.8 |
| btfn | 32 | 16 | 16098875 | 83.8 |
| btfn | 32 | 14 | 17911458 | 93.3 |
| nt | 2 | 32 | 42522619 | 221.5 |

Policies: `nt` always not taken; `btb` taken on every BTB hit; `btfn` BTB hit: jumps taken, branches
taken when backward; `bimod` BTB hit: jumps taken, branches follow a 2-bit counter in the entry.

## Area and frequency (whole core, nangate45)

| entries | SPAN_W | area (um^2) | fmax (MHz) |
|---|---|---|---|
| 0 (stage 3, not taken) | - | 21626 | 715 |
| 2 | 32 | 22608 | 648 |
| 4 | 32 | 23514 | 715 |
| 8 | 32 | 25362 | 736 |
| 16 | 32 | 28804 | 703 |
| 4 | 16 | 22552 | 712 |
| 8 | 16 | 23540 | 678 |
| 8 | 14 | 23636 | 672 |
| 16 | 14 | 24659 | 711 |
| **8** | **16** | **23623** | **813** (after the EXU misprediction compare was restructured) |

A full-width entry costs about 230 um^2. fmax varies by about 5% between runs of the same design;
in every case the critical path was EXU's misprediction check (branch compare, then a 32-bit compare
of the actual next PC with the predicted one), not the BTB lookup. Computing both target compares in
parallel with the branch condition, which then only selects between them, raised fmax to 813 MHz.

## Choice

Bimodal, 8 entries, SPAN_W 16: 14.35 M mispredictions against 42.52 M for not taken (-66%). 16 entries
would save another 0.5 M (SPAN_W 14) at 1100 um^2 more, leaving under 400 um^2 of the 25000 budget.
