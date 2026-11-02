pkg() {
  # The programs Fedora's procps-ng has, uptime among them (coreutils leaves
  # it out), skill and snice. kill is util-linux's (BUILD.md "System stage").
  # w reads sessions from logind (--with-systemd), not utmp. No translated
  # man pages: configure finds no po4a.
  pkg_autotools \
    ac_cv_prog_PO4A= \
    --disable-static \
    --disable-kill \
    --enable-skill \
    --enable-watch8bit \
    --enable-sigwinch \
    --with-systemd
}
