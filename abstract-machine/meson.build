# AbstractMachine: the `am` and `klib` libraries plus the flags every AM program
# is compiled and linked with. The cross file names the ARCH; everything that
# depends on it is chosen here, in one place.

arch = meson.get_external_property('am_arch')

if arch == 'riscv32-nemu'
  isa      = 'riscv32'
  platform = 'nemu'
  march    = ['-march=rv32im_zicsr', '-mabi=ilp32']
elif arch == 'riscv32e-npc'
  isa      = 'riscv32e'
  platform = 'npc'
  march    = ['-march=rv32e_zicsr', '-mabi=ilp32e']
elif arch == 'riscv32i-npc'
  isa      = 'riscv32i'
  platform = 'npc'
  march    = ['-march=rv32i_zicsr', '-mabi=ilp32']
else
  error('unsupported am_arch "@0@"'.format(arch))
endif

## Compile flags, shared by am, klib and every program

# Applied to C and to .S, which Meson preprocesses with the C compiler.
codegen_args = march + ['-fno-pic', '-mcmodel=medany', '-mstrict-align']

am_c_args = codegen_args + [
  '-std=gnu11', '-O2', '-Wall', '-Werror',
  '-D__ISA__="@0@"'.format(isa),
  '-D__ISA_@0@__'.format(isa.to_upper()),
  '-D__ARCH__=@0@'.format(arch),
  '-D__ARCH_@0@'.format(arch.to_upper().replace('-', '_')),
  '-D__PLATFORM__=@0@'.format(platform),
  '-D__PLATFORM_@0@'.format(platform.to_upper()),
  '-DARCH_H="arch/riscv.h"',
  '-fno-asynchronous-unwind-tables', '-fno-builtin', '-fno-stack-protector',
  '-Wno-main', '-U_FORTIFY_SOURCE', '-fvisibility=hidden',
  '-static', '-fdata-sections', '-ffunction-sections',
  # tools/insert-arg.py patches mainargs into the image by finding this string.
  '-DMAINARGS_MAX_LEN=64',
  '-DMAINARGS_PLACEHOLDER="The insert-arg rule in Makefile will insert mainargs here."',
]

am_inc_dirs = ['am/include', 'klib/include']

if platform == 'nemu'
  am_c_args += '-DISA_H="riscv/riscv.h"'
  am_inc_dirs += 'am/src/platform/nemu/include'
endif

am_inc = include_directories(am_inc_dirs)

## Link flags

linker_script = files('scripts/linker.ld')

# Linked through the gcc driver; -nostdlib keeps it from adding crt*.o, libc
# and libgcc, so the result matches a plain `ld` link of the objects and archives.
am_link_args = march + [
  '-nostdlib', '-static',
  # The distro gcc passes --build-id by default; linker.ld has no rule for that
  # note, so it would land in the image as an orphan section.
  '-Wl,--build-id=none',
  '-Wl,-z,noexecstack',
  '-Wl,-T,@0@'.format(linker_script[0].full_path()),
  '-Wl,--defsym=_pmem_start=0x80000000',
  '-Wl,--defsym=_entry_offset=0x0',
  '-Wl,--gc-sections',
  '-Wl,-e,_start',
]

## Libraries

if platform == 'nemu'
  am_srcs = files(
    'am/src/platform/nemu/trm.c',
    'am/src/platform/nemu/ioe/ioe.c',
    'am/src/platform/nemu/ioe/timer.c',
    'am/src/platform/nemu/ioe/input.c',
    'am/src/platform/nemu/ioe/gpu.c',
    'am/src/platform/nemu/ioe/audio.c',
    'am/src/platform/nemu/ioe/disk.c',
    'am/src/platform/nemu/mpe.c',
    'am/src/riscv/nemu/start.S',
    'am/src/riscv/nemu/cte.c',
    'am/src/riscv/nemu/trap.S',
    'am/src/riscv/nemu/vme.c',
  )
else
  am_srcs = files(
    'am/src/riscv/npc/start.S',
    'am/src/riscv/npc/trm.c',
    'am/src/riscv/npc/ioe.c',
    'am/src/riscv/npc/timer.c',
    'am/src/riscv/npc/input.c',
    'am/src/riscv/npc/cte.c',
    'am/src/riscv/npc/trap.S',
    'am/src/platform/dummy/vme.c',
    'am/src/platform/dummy/mpe.c',
    # NPC has no M extension and links without libgcc; these supply the
    # division and multiplication helpers gcc emits calls to.
    'am/src/riscv/npc/libgcc/div.S',
    'am/src/riscv/npc/libgcc/muldi3.S',
    'am/src/riscv/npc/libgcc/multi3.c',
    'am/src/riscv/npc/libgcc/ashldi3.c',
    'am/src/riscv/npc/libgcc/unused.c',
  )
endif

klib_srcs = files(
  'klib/src/cpp.c',
  'klib/src/int64.c',
  'klib/src/stdio.c',
  'klib/src/stdlib.c',
  'klib/src/string.c',
)

am_lib = static_library('am', am_srcs,
  c_args: am_c_args,
  include_directories: [include_directories('am/src'), am_inc],
  implicit_include_directories: false,
)

klib_lib = static_library('klib', klib_srcs,
  c_args: am_c_args,
  include_directories: am_inc,
  implicit_include_directories: false,
)

## What an AM program uses: link it as `executable(..., dependencies: am_dep)`

am_dep = declare_dependency(
  compile_args: am_c_args,
  include_directories: am_inc,
  link_with: [am_lib, klib_lib],
  link_args: am_link_args,
)

objcopy = find_program('objcopy')
objdump = find_program('objdump')

## The simulator that runs AM programs for `meson test`, built by its own Makefile

if platform == 'nemu'
  am_runner = find_program(meson.project_source_root() / get_option('nemu'), required: false)
else
  am_runner = find_program(meson.project_source_root() / get_option('npc'), required: false)
endif
