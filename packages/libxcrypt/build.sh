pkg() {
  pkg_autotools \
    --enable-hashes=strong,glibc \
    --enable-obsolete-api=no \
    --disable-static \
    --disable-failure-tokens
}
