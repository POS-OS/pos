pkg() {
  # Git checkouts lack generated files such as libdw/known-dwarf.h; maintainer
  # mode regenerates them (needs flex, bison, gawk).
  pkg_autotools \
    --enable-maintainer-mode \
    --disable-debuginfod \
    --enable-libdebuginfod=dummy \
    --disable-static
}
