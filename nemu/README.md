# NEMU

NEMU(NJU Emulator) is a simple but complete full-system emulator designed for teaching purpose.
Currently it supports x86, mips32, riscv32 and riscv64.
To build programs run above NEMU, refer to the [AM project](https://github.com/NJU-ProjectN/abstract-machine).

The main features of NEMU include
* a small monitor with a simple debugger
  * single step
  * register/memory examination
  * expression evaluation without the support of symbols
  * watch point
  * differential testing with reference design (e.g. QEMU)
  * snapshot
* CPU core with support of most common used instructions
  * x86
    * real mode is not supported
    * x87 floating point instructions are not supported
  * mips32
    * CP1 floating point instructions are not supported
  * riscv32
    * only RV32IM
  * riscv64
    * only RV64IM
  * gameboy
    * TODO
* memory
* paging
  * TLB is optional (but necessary for mips32)
  * protection is not supported
* interrupt and exception
  * protection is not supported
* 5 devices
  * serial, timer, keyboard, VGA, audio
  * most of them are simplified and unprogrammable
* 2 types of I/O
  * port-mapped I/O and memory-mapped I/O

## Experimental JIT-IR Engine (riscv32)

This repository now includes an experimental JIT-style execution path for `riscv32`:
`ENGINE_JIT_IR` translates guest instructions into lightweight IR blocks (TBs), executes them, and falls back to the interpreter for unsupported cases.

### Enable JIT-IR

JIT-IR currently requires `riscv32` + `TARGET_NATIVE_ELF`.

```sh
make menuconfig
```

In menuconfig:
- `Base ISA` -> `riscv`
- `NEMU execution engine` -> `JIT IR (riscv32, batch mode)`
- `Build target` -> `Executable on Linux Native`

Then build and run:

```sh
export NEMU_HOME=$PWD
export CCACHE_DISABLE=1
make -j$(nproc) NEMU_HOME=$PWD
make run NEMU_HOME=$PWD IMG=/path/to/image.bin
```

### Behavior and Limitations

- JIT-IR is currently for `riscv32` only.
- It is designed for batch-style execution paths.
- Unsupported instructions at translation points automatically fall back to interpreter execution.
- TB cache validity is checked with instruction snapshots; changed code triggers re-translation.
- With `CONFIG_JIT_STATS=y`, runtime logs include `tb_hit/tb_miss/fallback` and JIT instruction counts.
- This repo's default `make` may trigger tracer git commits. If you are in a restricted environment and see `.git/index.lock` permission errors, it is expected and does not affect the built binary.

### Quick A/B Comparison

Use the same image and switch engine in menuconfig:
1. `Interpreter`
2. `JIT IR`

Compare:
- `simulation frequency` in final statistics
- JIT counters printed at program end (JIT run)

## 实验性 JIT-IR 引擎（riscv32）

本仓库已经加入一个面向 `riscv32` 的实验性 JIT 执行路径：
`ENGINE_JIT_IR` 会将访客指令翻译为轻量 IR 翻译块（TB）执行；遇到暂未支持的情况会自动回退到解释器执行。

### 如何启用 JIT-IR

当前 JIT-IR 需要 `riscv32` + `TARGET_NATIVE_ELF`。

```sh
make menuconfig
```

在 menuconfig 中选择：
- `Base ISA` -> `riscv`
- `NEMU execution engine` -> `JIT IR (riscv32, batch mode)`
- `Build target` -> `Executable on Linux Native`

然后编译并运行：

```sh
export NEMU_HOME=$PWD
export CCACHE_DISABLE=1
make -j$(nproc) NEMU_HOME=$PWD
make run NEMU_HOME=$PWD IMG=/path/to/image.bin
```

### 当前行为与限制

- JIT-IR 目前仅支持 `riscv32`。
- 当前实现面向批处理执行路径。
- 在翻译点遇到不支持指令时，会自动回退到解释器。
- TB 缓存通过指令快照校验；代码变化会触发重新翻译。
- 当 `CONFIG_JIT_STATS=y` 时，结束统计会输出 `tb_hit/tb_miss/fallback` 等指标。
- 本仓库默认 `make` 可能触发 tracer 的 git 提交流程；若在受限环境出现 `.git/index.lock` 权限报错，通常不影响二进制生成。

### 快速做 A/B 对比

使用同一镜像，在 menuconfig 中切换执行引擎：
1. `Interpreter`
2. `JIT IR`

重点对比：
- 末尾统计中的 `simulation frequency`
- JIT 运行时额外输出的 JIT 统计信息
