pkg() {
  # The ext2/3/4 tools: mke2fs, e2fsck (fsck.ext4 for systemd-fsck of the
  # root), resize2fs, tune2fs, debugfs, e2scrub, and their libraries
  # (libext2fs, libcom_err, libss, libe2p). configure is committed. libuuid
  # and libblkid are util-linux's, as are fsck and uuidd. No FUSE (fuse2fs,
  # fuse4fs) or libarchive (mke2fs -d from a tarball). e2scrub's units and
  # udev rule go to /pos/lib; its timer stands in for the cron file.
  pkg_autotools \
    --enable-elf-shlibs \
    --disable-libuuid \
    --disable-libblkid \
    --disable-uuidd \
    --disable-fsck \
    --disable-e2initrd-helper \
    --disable-fuse2fs \
    --disable-fuse4fs \
    --without-libarchive \
    --with-crond-dir=no \
    --with-udev-rules-dir="${prefix}/lib/udev/rules.d" \
    --with-systemd-unit-dir="${prefix}/lib/systemd/system"
}
