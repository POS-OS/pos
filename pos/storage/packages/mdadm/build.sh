pkg() {
  # Linux software RAID: mdadm and mdmon, their udev rules (incremental
  # assembly), units and shutdown hook. Its own Makefile, which takes the
  # paths as variables; programs in /pos/sbin, which the rules and units
  # name. CFLAGS as POS's (CXFLAGS), its warnings without -Werror, which a
  # newer compiler than upstream's can trip.
  pkg_sync_src
  local -a vars=(
    CXFLAGS="$CFLAGS"
    CWFLAGS="-Wall -Wstrict-prototypes -Wextra -Wno-unused-parameter -Wformat -Wformat-security"
    BINDIR="${prefix}/sbin"
    MANDIR="${prefix}/share/man"
    MISCDIR="${prefix}/share/mdadm"
    LIB_DIR="${prefix}/libexec/mdadm"
    SYSTEMD_DIR="${prefix}/lib/systemd/system"
    UDEVDIR="${prefix}/lib/udev"
  )
  pkg_compile "${vars[@]}"
  pkg_install "${vars[@]}" install-systemd
}
