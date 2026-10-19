pkg() {
  # The programs Fedora's procps-ng has, uptime among them (coreutils leaves
  # it out), skill and snice. kill is util-linux's (BUILD.md "System stage").
  # w reads sessions from logind (--with-systemd), not utmp.
  pkg_autotools \
    --disable-static \
    --disable-kill \
    --enable-skill \
    --enable-watch8bit \
    --enable-sigwinch \
    --with-systemd
}
