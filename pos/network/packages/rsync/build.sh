pkg() {
  # popt and zlib from POS, not rsync's included copies. Compression with
  # zstd and zlib, checksums with OpenSSL; no lz4, xxhash or IDN (libidn2),
  # which POS lacks: configure stops at an optional library it does not
  # find unless the feature is turned off. The daemon's units (packaging/systemd) are installed with
  # POS's path to rsync.
  pkg_autotools \
    --with-included-popt=no \
    --with-included-zlib=no \
    --enable-zstd \
    --enable-openssl \
    --disable-lz4 \
    --disable-xxhash \
    --enable-acl-support \
    --enable-xattr-support \
    --enable-ipv6 \
    --disable-idn
  local unit
  install -d "${dest_dir}${prefix}/lib/systemd/system"
  for unit in rsync.service rsync@.service rsync.socket; do
    sed "s|/usr/bin/rsync|${prefix}/bin/rsync|g" "packaging/systemd/$unit" \
      >"${dest_dir}${prefix}/lib/systemd/system/$unit"
  done
  ! grep -q /usr/bin "${dest_dir}${prefix}"/lib/systemd/system/rsync* ||
    { echo "rsync: units still name /usr/bin" >&2; exit 1; }
}
