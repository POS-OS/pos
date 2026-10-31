pkg() {
  # kill comes from util-linux and uptime from procps (BUILD.md "System stage").
  # hostname is not installed by default; nothing else in the base provides it.
  # libgmp gives expr and factor arbitrary precision. gmp is a core library.
  pkg_autotools \
    --enable-no-install-program=kill,uptime \
    --enable-install-program=hostname \
    --with-openssl=yes \
    --with-libgmp \
    --with-libgmp-prefix="$prefix" \
    --without-selinux
}
