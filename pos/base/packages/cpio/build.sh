pkg() {
  # GNU cpio, which dracut makes the initramfs archive with.
  pkg_autotools
  # rmt is tar's: both build it from paxutils into libexec, where cpio
  # finds tar's (BUILD.md "Overlapping binaries").
  rm -f "${dest_dir}${prefix}/libexec/rmt"
}
