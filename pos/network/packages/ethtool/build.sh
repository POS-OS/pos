pkg() {
  # The netlink interface (libmnl) is what newer settings need; the ioctl
  # one stays as the fallback.
  pkg_autotools \
    --enable-netlink \
    --enable-pretty-dump \
    --with-bash-completion-dir="${prefix}/share/bash-completion/completions"
}
