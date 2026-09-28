# RV32 原地补丁原生执行引擎 —— 事后总结

状态：已否决 —— 未实现。本文档作为设计历史保留。

（英文版见 `rv32-native-execution-engine.md`，两份内容一致。）

## 原方案概述

RV32I+M 的指令编码几乎全部是合法的 RV64 指令，位模式完全相同。在 RV64
Linux 宿主（VisionFive 2，U74，sv39）上，原则上可以把 RV32 裸机镜像
（`riscv32-nemu`，定长 4 字节指令，无 C 扩展）做一次加载时的等长补丁扫描
后原生执行，再用三个信号处理器（SIGTRAP 处理停机、SIGSEGV 处理 MMIO、
SIGILL 兜底）覆盖残余语义。

目标：以约一千行独立 Rust、零代码生成，让 NEMU/NPC 消费的那份二进制本体
跑出接近原生的速度。

方案在实现前被否决。两个相互独立的理由：

1. **透明执行在 Linux 下结构性不可能**（任何 sv39/sv48/sv57 宿主都一样，
   见下文"地址空间之墙"）。
2. **功能性需求不存在**：AM 的平台抽象让任何程序都可以直接以
   `ARCH=native` 重编到 VF2 上跑。rv32 二进制唯一不可替代的场合是作为
   在研模拟器的测试输入——而那个场合要的是可信和可观测，不是快。

## 已验证、仍然成立的部分

以下分析结论是可靠的，存档备查：

- **符号扩展不变式**。guest 值始终以符号扩展形式放在 64 位宿主寄存器里，
  所有比较指令（`slt/sltu/slti/sltiu` 及条件分支）因此零补丁正确。符号
  扩展对两种序都保序：bit31=0 的值映到 u64 空间底部（只是加前导零），
  bit31=1 的值映到顶部（共同的全 1 前缀），块内块间顺序都保持。signed
  半边就是补码保值；unsigned 半边是不直观的部分，必须显式验证（例如
  `0x7FFFFFFF` 与 `0x80000000` 分别映为 `0x00000000_7FFFFFFF` 和
  `0xFFFFFFFF_80000000`，在 u64 序下大小关系不变）。
- **W 形替换**。`addw`/`sllw` 等"取低 32 位运算、结果符号扩展写回"，恰好
  等于 RV32 语义，也恰好维护不变式。`mul/div/rem` 族同样有 W 形。
- **对真实目标镜像的特权指令实证扫描**：cpu-tests 和 hello 含零条
  `csr`/`ecall`/`mret`；yield-os 恰好 9 条（`csrw mtvec`、`ecall`、
  `csrr mcause/mstatus/mepc`、`csrw mstatus` ×2、`csrw mepc`、`mret`）。
  一个只含 {mtvec, mcause, mstatus, mepc} 的最小影子 CSR 模型即可覆盖
  CTE 程序。
- **栈初始化**：AM 的 `start.S` 自己按链接脚本设 `sp`（`_stack_pointer`
  = bss 尾 + 0x8000）；引擎只需设 pc 并清零寄存器，对齐 NEMU 复位状态。
- **陷阱处理机制可行**：信号处理器可以通过 `ucontext_t` 改写保存的现场
  （`gregs[0]` = pc，`gregs[n]` = xn），`sigreturn` 会恢复 handler 留下
  的任何值——yuzu NCE 的 SIGUSR2/SIGURG 线程推入/抢占用的正是这个机制。

## 困难一（可解）：XLEN 分歧的算术

`add` 在 RV64 上 64 位回绕，RV32 语义要求 32 位回绕。由 W 形补丁加上述
不变式解决。`mulh` 族没有 W 形，必须补丁成"保留寄存器字段的非法编码"
并在 SIGILL 里模拟（补丁成全零会毁掉 rd/rs1/rs2——原 spec 选
`0x00000000` 是错的；它在支持 C 扩展的 U74 上还会解码成 16 位
`c.unimp`）。

## 困难二（可解但真实）：特权指令

目标是 `rv32im_zicsr`，使用 CTE 的程序会执行 `ecall`、CSR 访问和
`mret`。在宿主上，U-mode 的 `ecall` **就是 Linux 系统调用指令本体**——
它不会 trap，而是用 guest 控制的参数发起一次真实系统调用（yield-os 的
`yield()` 以 `a7=-1` 执行 `ecall`，会静默返回 `-ENOSYS`）。这正是目标
里明令禁止的静默错误。CSR/`mret` 会 trap（SIGILL）。借鉴 yuzu 的修法是
加载时把这些点补丁成 trampoline 或非法编码，运行时维护影子 M 态。是真实
工作量，但有界（yield-os 共 9 个点）。

## 困难三（致命）：地址空间之墙

### 宿主布局约束

RISC-V Linux 按 svN 范围顶端把 canonical 虚拟地址空间切成两半（内核文档
`Documentation/arch/riscv/vm-layout.rst`）：

| 模式 | 用户空间 | 内核空间 |
|---|---|---|
| sv39 | `0x00000000_00000000` – `0x0000003F_FFFFFFFF` | `0xFFFFFFC0_00000000` – `0xFFFFFFFF_FFFFFFFF` |
| sv48 | `0x0` – `0x00007FFF_FFFFFFFF` | `0xFFFF8000_00000000` – ... |
| sv57 | `0x0` – `0x00FFFFFF_FFFFFFFF` | `0xFF000000_00000000` – ... |

任何模式下，bits 63:32 全 1 的地址都在内核半部。用户态 `mmap` 到那里
必然失败。

### 两种指针形态不可避免地共存

guest RAM 在 `0x80000000`（bit 31 = 1）。这不是本项目自己的决定，而是
整个 RISC-V 生态的通用约定：QEMU virt 机器的 DRAM 起始地址和复位向量，
被 OpenSBI 的跳转目标、Linux riscv 内核加载地址、xv6-riscv 的 KERNBASE
一路继承下来，进而钉进 NEMU 的 `CONFIG_MBASE`、AM 的链接脚本和 NPC 的
地址译码。任何"挪基址重链接"的把戏都得重编引擎本想运行的那份二进制，
也就消解了它仅存的存在意义。把镜像放在原地址原地执行是可映射的，但
指针经两条路径进入寄存器：

- **pc 来源**（`auipc`/`jal`，包括所有 `la`）：宿主拿真实的 64 位 pc
  做加法，产出零扩展形态 `0x00000000_8xxxxxxx`。
- **内存来源**（`lw`）：RV64 的 `lw` 做符号扩展，产出
  `0xFFFFFFFF_8xxxxxxx`。

要让 `auipc` 的产物等于符号扩展形态，代码必须映射在
`0xFFFFFFFF_80000000` 本身——内核半部，不可能。于是两种形态共存，且
哪一种都消灭不掉。

### 最小例子 A：`ret` 跳进内核半部

```asm
# 调用方序言/尾声，最普通不过的代码
sw   ra, 12(sp)          # 只存 0x00000000_80000123 的低 32 位
lw   ra, 12(sp)          # 读回 0x80000123，符号扩展：
                         # ra = 0xFFFFFFFF_80000123
ret                      # jalr x0, 0(ra)：到
                         # 0xFFFFFFFF_80000123 取指 -> 缺页 -> SIGSEGV
```

handler 可以救（截断、改 `gregs[0]`、sigreturn），但每次返回一次信号
往返，near-native 目标直接报废。热路径可以补丁（`lw ra` -> `lwu ra`
等长且由 ABI 保证安全），但溢出到内存的函数指针、数据指针仍走慢路径。

### 最小例子 B：防不住的那个——跨形态比较

```c
// guest 语义：cb == &my_handler 为真
if (cb == &my_handler) { ... }
```

```asm
lw   a5, ...          # cb，经内存转了一手：0xFFFFFFFF_80000abc
auipc a4, ...         # ┐ &my_handler，pc 来源：0x00000000_80000abc
addi a4, a4, ...      # ┘
beq  a5, a4, ...      # 64 位比较：不等 -> 走错分支，且无声无息
```

不访存、不 fault、没有任何 hook 点。三条逃生路全部堵死：

- 消灭零扩展形态 → 代码得放在 `0xFFFFFFFF8...`（内核半部，任何 sv
  模式都不可能）；
- 消灭符号扩展形态 → 得把读指针的 lw 补丁成 `lwu`，但一条 `lw` 编码
  无法静态区分自己读的是指针还是数据；
- 拦截比较 → `beq` 永远不会 trap。

### 为什么"把所有 load 改成零扩展"也不行

全部 `lw`->`lwu`（及 `lb`->`lbu`、`lh`->`lhu`）能让指针形态统一，但
会打破有符号数据比较，而后者无法等长补丁：

```asm
# guest：t0 = -1，t1 = 1；slt a0, t0, t1 必须为 1
# 零扩展后：t0 = 0x00000000_FFFFFFFF（巨大的正数），
# slt（有符号 64 位）得出 0。错了，而且无声无息。
```

符号扩展的数据（`slt` 需要）和零扩展的指针（可映射地址需要）对同一批
load 指令提出了互相矛盾的要求。

### 结构性结论

NEMU 和 qemu-user 能实现透明，恰恰因为它们**不**共享宿主的地址空间和
寄存器宽度。这个引擎的全部前提是"足够接近所以可以共享"；透明性恰恰死
在共享上。yuzu NCE 从不面对这个问题，因为它的 guest 本来就是 64 位进
程，指针从一开始就住在低半部——而它对 32 位 guest 的答案是回退 JIT，
事后看那是同一堵墙。

## 务实（非透明）版本本会长什么样

存档备查，万一将来放松目标重提此事：

- 在 `0x80000000` 原地执行；无镜像映射，无 arena；
- 数据符号扩展不变式，W 形补丁，`mulh` 用保留字段的非法编码 + SIGILL
  模拟；
- `lw ra` -> `lwu ra` 补丁；其余形态 S 解引用走 SIGSEGV 截断+模拟兜底；
- `ecall`/CSR 走 trampoline 或 SIGILL，影子 {mtvec, mcause, mstatus,
  mepc}；
- 跨形态比较风险作为已知缺陷接受，实证审计；
- 验证：cpu-tests 停机码对齐 NEMU、microbench 出 Marks、yield-os。

## 补记："真正的"解法是怎么做的（硬件兼容模式）

ARM 和 x86 把 32 位兼容做在**硅片里**：ARMv8 有一整个第二执行态
（EL0 的 AArch32）；x86-64 用代码段描述符一位进入兼容模式。RISC-V 在
特权架构里设计了同款机制：可写的 `sstatus.UXL` 让 U-mode 以 XLEN=32
执行。Linux 在 5.19 合并了 riscv `CONFIG_COMPAT` 以在其上跑 rv32 用户
态程序；T-Head 为了实现 UXL=32 专门修改了硬件（见
[RISC-V 国际基金会博客](https://riscv.org/blog/run-32-bit-applications-on-64-bit-linux-kernel-liu-zhiwei-guo-ren-t-head-division-of-alibaba-cloud/)）。

VF2 实测（2026-09，内核 6.12.5-starfive，U74-mc，sv39）：静态链接的
rv32 ELF 在内核已开启 `CONFIG_COMPAT=y` 和 `CONFIG_COMPAT_BINFMT_ELF=y`
的情况下仍然 `Exec format error`——即 U74 没有实现可写 UXL。透明引擎
作为硬件功能真实存在，只是这块芯片里没有它。

注意硬件成本其实很小，正因为 RV64 已经包含了 32 位数据通路：W 形指令
（addw/sllw/...）就是"32 位回绕 + 符号扩展"的现成通路，UXL=32 主要
是在这些通路、移位量宽度、地址截断、CSR 宽度上加选择线——流水线里的
一根模式电线，不是第二个 ALU。

## 教训

- **SW/HW 边界才是真正的设计决策。** 同一个功能两侧都能实现，但代价
  结构不同：硬件的每指令语义切换是零成本的（模式位是每条指令都经过
  的物理电线）；软件只能在拦截点（trap/fault）上行动。RV32-on-RV64
  兼容需要在*每条 load、每条比较*上翻转语义——这个频率只有硬件侧付
  得起。我们的软件方案试图复刻一根只有硅片能拉的电线。
- **借来的技术连前提一起借。** yuzu 的 patch / trampoline / 信号
  handler 工具箱成立，是因为其前提（同宽同 ISA）让分歧是例外。宽度
  不匹配时分歧是结构性的——存在于每条 load——为例外设计的工具箱
  修不了常态。
- **agent 起草的 spec，每条承重事实都要实证。** 原 spec 把"在
  `0xFFFFFFFF80000000` 镜像映射"列为*已确认决定*，但它在任何 RISC-V
  Linux 上都不成立。内核 vm-layout 文档一页纸就能在草稿期杀死它。
- **先验证宿主行为假设**（可映射 VA 范围；U-mode `ecall`/CSR 到底会
  怎样），再设计任何依赖它们的东西。
- **反汇编胜过对二进制内容的推理**——objdump 扫描几分钟就终结了 CSR
  范围之争。
- **透明性目标才是最脆弱的部分。** 性能目标可以优雅降级；静默语义分歧
  的目标是结构性失败，没有中间态。
