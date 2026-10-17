pkg() {
  # The magic database is compiled with the file binary built here, which is
  # why file must be a native build. seccomp sandboxing uses libseccomp from
  # this stage.
  pkg_autotools \
    --disable-static \
    --enable-libseccomp \
    --enable-zlib \
    --enable-bzlib \
    --enable-xzlib \
    --enable-zstdlib \
    --disable-lzlib \
    --disable-lrziplib
}
