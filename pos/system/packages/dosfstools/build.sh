pkg() {
  # FAT tools: mkfs.fat and fsck.fat (fsck.vfat for systemd-fsck of the
  # ESP), fatlabel, with the mkdosfs, mkfs.vfat, dosfsck, fsck.vfat and
  # dosfslabel names Fedora also has.
  pkg_autotools --enable-compat-symlinks
}
