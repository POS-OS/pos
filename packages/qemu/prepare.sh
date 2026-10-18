# QEMU's configure, offline (--disable-download), wants its keycodemapdb
# subproject in the tree, as a release tarball has it. It is fetched here,
# at the revision its wrap names; the guest agent needs no other subproject.
#
# The guest agent runs poweroff, halt, reboot, shutdown and hwclock by
# their /sbin paths (guest-shutdown, guest-set-time); POS has them in
# /pos/sbin (systemd, util-linux). What it runs by name (chpasswd) is
# found in the service's PATH.

prep() {
  meson subprojects download keycodemapdb
  rm -rf subprojects/keycodemapdb/.git
  [[ -f subprojects/keycodemapdb/README ]] || {
    echo "qemu: keycodemapdb not downloaded" >&2
    exit 1
  }

  sed -i -E 's#"/sbin/(poweroff|halt|reboot|shutdown|hwclock)"#"/pos/sbin/\1"#' qga/commands-posix.c
  [[ $(grep -cE '"/pos/sbin/(poweroff|halt|reboot|shutdown|hwclock)"' qga/commands-posix.c) == 5 ]] &&
    ! grep -q '"/sbin/' qga/commands-posix.c || {
    echo "qemu: qga/commands-posix.c paths not as expected" >&2
    exit 1
  }
}
