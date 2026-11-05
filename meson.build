project('ysyx-workbench', 'c',
  meson_version: '>=1.12',
  default_options: [
    # Every flag the AM programs need is spelled out in abstract-machine/meson.build.
    # These keep Meson from adding its own: no -O0 -g, no -Wall duplicate,
    # no -fPIC/-pie, and no --as-needed/--no-undefined on a bare-metal link.
    'buildtype=plain',
    'warning_level=0',
    'b_staticpic=false',
    'b_pie=false',
    'b_asneeded=false',
    'b_lundef=false',
  ],
)

subdir('abstract-machine')
subdir('am-kernels')
