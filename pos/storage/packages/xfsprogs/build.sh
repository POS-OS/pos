pkg() {
  # XFS tools: mkfs.xfs, xfs_repair, xfs_growfs, xfs_db, xfs_io, xfs_scrub
  # (with ICU's Unicode checks) and xfs_healer, their units and udev rule.
  # mkfs.xfs reads its configuration files with inih. Its install takes the
  # staging directory as DIST_ROOT. xfs_scrub_all and xfs_protofile are
  # Python scripts, which POS cannot run: they are removed, with the
  # xfs_scrub_all units; xfs_scrub@.service still checks a mounted file
  # system. No editline (xfs_db and xfs_io line editing).
  pkg_configure \
    --disable-lib64 \
    --disable-editline \
    --enable-scrub \
    --enable-libicu=yes \
    --enable-healer \
    --with-crond-dir=no \
    --with-systemd-unit-dir="${prefix}/lib/systemd/system" \
    --with-udev-rule-dir="${prefix}/lib/udev/rules.d"
  pkg_compile
  make DIST_ROOT="$dest_dir" install
  find "$dest_dir" \( -name 'xfs_scrub_all*' -o -name 'xfs_protofile*' \) -delete
}
