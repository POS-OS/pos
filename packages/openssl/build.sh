pkg() {
  pkg_sync_src

  ./config --prefix="$prefix" \
           --openssldir="${sysconfdir}/ssl" \
           --libdir=lib \
           shared \
           zlib-dynamic
  pkg_compile
  pkg_install MANSUFFIX=ssl
}
