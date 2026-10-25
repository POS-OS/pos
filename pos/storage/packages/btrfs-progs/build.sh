pkg() {
  # Btrfs tools: btrfs, mkfs.btrfs, btrfs-convert (from ext2/3/4, with
  # e2fsprogs' libraries), btrfstune, fsck.btrfs, libbtrfs and
  # libbtrfsutil, the udev rules, and the man pages (Sphinx). Checksums
  # with OpenSSL; zstd and zlib compression. No LZO: POS has no liblzo2
  # (lzo is released only as tarballs), so btrfs restore, receive and
  # mkfs --rootdir cannot handle LZO-compressed extents. No Python
  # bindings.
  pkg_autotools \
    --disable-static \
    --disable-lzo \
    --disable-python \
    --enable-zstd \
    --enable-libudev \
    --enable-convert \
    --with-convert=ext2 \
    --with-crypto=openssl \
    --enable-documentation
}
