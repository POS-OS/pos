pkg() {
  # The console's keyboard layouts and fonts: loadkeys, setfont, dumpkeys,
  # kbd_mode and the other kbd programs, which systemd-vconsole-setup runs
  # with /etc/vconsole.conf's KEYMAP and FONT (localectl, systemd-firstboot
  # --keymap), and dracut's i18n module puts in the initramfs.
  #
  # The data (keymaps, consolefonts, consoletrans, unimaps) goes to
  # /pos/share/kbd, the programs' built-in data directory; systemd's list of
  # keymap directories and dracut's kbddir name it (systemd's build.sh,
  # dracut's 01-dist.conf). It is installed uncompressed, so loading it needs
  # no decompression library or program. vlock (a PAM program with a PAM
  # configuration of its own) and the tests are left out; xkb conversion
  # needs xkbcommon, which POS does not have.
  pkg_autotools \
    --datadir="${prefix}/share/kbd" \
    --disable-compress \
    --without-zlib \
    --without-bzip2 \
    --without-lzma \
    --without-zstd \
    --disable-vlock \
    --disable-xkb \
    --disable-tests
}
