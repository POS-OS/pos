pkg() {
  pkg_sync_src

  # Data only. crypt(3) and friends are documented by libxcrypt, which is
  # already in core-libs; drop the man-pages copies so the two do not clash.
  rm -f man/man3/crypt*
  pkg_install -R prefix="$prefix"
}
