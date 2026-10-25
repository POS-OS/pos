pkg() {
  # The device-mapper persistent data tools lvm2 runs for thin and cache
  # volumes (thin_check, cache_repair, ...): one program, pdata_tools, and
  # a link per tool. No developer tools (devtools) or io_uring. Its
  # Makefile installs the build's program, unstripped (_pkg_finish splits
  # the debug info), and makes the man pages with its txt2man.
  pkg_cargo
  pkg_install PREFIX="$prefix" PDATA_TOOLS="$cargo_out/pdata_tools" STRIP=true
}
