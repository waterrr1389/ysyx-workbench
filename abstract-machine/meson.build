# AbstractMachine: the `am` and `klib` libraries plus the flags every AM program
# is compiled and linked with. The cross file names the ARCH (no cross file
# means native); everything that depends on it is chosen in this file.

arch = meson.get_external_property('am_arch', 'native')

## Per-ARCH settings

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
elif arch == 'native'
  isa      = 'native'
  platform = ''
else
  error('unsupported am_arch "@0@"'.format(arch))
endif

bare_metal = arch != 'native'

# Bare-metal images carry this string; tools/insert-arg.py finds it in the .bin
# and overwrites it with the program's mainargs. native reads $mainargs instead.
mainargs_max_len = 64
mainargs_placeholder = 'The insert-arg rule in Makefile will insert mainargs here.'

## Compile flags, shared by am, klib and every program

# -std comes from the c_std and cpp_std options in the top-level meson.build.
am_c_args = [
  '-O2', '-Wall', '-Werror',
  '-D__ISA__="@0@"'.format(isa),
  '-D__ISA_@0@__'.format(isa.to_upper()),
  '-D__ARCH__=@0@'.format(arch),
  '-D__ARCH_@0@'.format(arch.to_upper().replace('-', '_')),
  '-fno-asynchronous-unwind-tables', '-fno-builtin', '-fno-stack-protector',
  '-Wno-main', '-U_FORTIFY_SOURCE', '-fvisibility=hidden',
]
am_inc_dirs = ['am/include', 'klib/include']
am_deps = []

if platform != ''
  am_c_args += [
    '-D__PLATFORM__=@0@'.format(platform),
    '-D__PLATFORM_@0@'.format(platform.to_upper()),
  ]
endif

if bare_metal
  am_c_args += march + [
    '-DARCH_H="arch/riscv.h"',
    '-fno-pic', '-mcmodel=medany', '-mstrict-align',
    '-static', '-fdata-sections', '-ffunction-sections',
    '-DMAINARGS_MAX_LEN=@0@'.format(mainargs_max_len),
    '-DMAINARGS_PLACEHOLDER="@0@"'.format(mainargs_placeholder),
  ]
else
  # native runs AM programs as Linux processes and draws through SDL.
  am_c_args += '-DARCH_H="arch/native.h"'
  am_deps += dependency('sdl2')
endif

if platform == 'nemu'
  am_c_args += '-DISA_H="riscv/riscv.h"'
  am_inc_dirs += 'am/src/platform/nemu/include'
endif

am_inc = include_directories(am_inc_dirs)

# Only C++ sources get these; programs pass them as `cpp_args: am_cpp_args`.
am_cpp_args = ['-ffreestanding', '-fno-rtti', '-fno-exceptions']

## Link flags

linker_script = files('scripts/linker.ld')

if bare_metal
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
else
  # Programs are linked with `pie: true`. The Makefile linked with g++, whose
  # driver adds -lm; native/ioe/gpu.c needs it.
  am_link_args = ['-Wl,-z,noexecstack', '-ldl', '-lm']
endif

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
elif platform == 'npc'
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
else
  am_srcs = files(
    'am/src/native/trm.c',
    'am/src/native/ioe.c',
    'am/src/native/cte.c',
    'am/src/native/trap.S',
    'am/src/native/vme.c',
    'am/src/native/mpe.c',
    'am/src/native/platform.c',
    'am/src/native/ioe/input.c',
    'am/src/native/ioe/timer.c',
    'am/src/native/ioe/gpu.c',
    'am/src/native/ioe/uart.c',
    'am/src/native/ioe/audio.c',
    'am/src/native/ioe/disk.c',
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
  pic: not bare_metal,
  c_args: am_c_args,
  include_directories: [include_directories('am/src'), am_inc],
  dependencies: am_deps,
  implicit_include_directories: false,
)

klib_lib = static_library('klib', klib_srcs,
  pic: not bare_metal,
  c_args: am_c_args,
  include_directories: am_inc,
  dependencies: am_deps,
  implicit_include_directories: false,
)

## What an AM program uses: link it as `executable(..., dependencies: am_dep)`

if bare_metal
  am_dep = declare_dependency(
    compile_args: am_c_args,
    include_directories: am_inc,
    link_with: [am_lib, klib_lib],
    link_args: am_link_args,
  )
else
  # native/platform.c sets up the process through constructors that nothing
  # references by name; a normal archive link would drop them.
  am_dep = declare_dependency(
    compile_args: am_c_args,
    include_directories: am_inc,
    link_whole: [am_lib, klib_lib],
    link_args: am_link_args,
    dependencies: am_deps,
  )
endif

## The simulator that runs AM programs for `meson test`, built by its own Makefile.
## native programs are ordinary executables and need none.

if bare_metal
  objcopy = find_program('objcopy')
  objdump = find_program('objdump')
  insert_arg = find_program('tools/insert-arg.py')
endif

if platform == 'nemu'
  am_runner = find_program(meson.project_source_root() / get_option('nemu'), required: false)
elif platform == 'npc'
  am_runner = find_program(meson.project_source_root() / get_option('npc'), required: false)
endif
