pkg() {
  # The man page format is given: configure otherwise copies what it finds
  # on the build host (gzip in Fedora). Terminal entries are looked up as
  # Fedora's ncurses does, local ones in /etc first, with POS's before
  # /usr/share/terminfo, where Fedora packages (foot-terminfo, kitty-terminfo,
  # ncurses-term) install theirs. The terminfo functions are a library of
  # their own, libtinfo.so.6, as in Fedora's ncurses-libs: Fedora's curses
  # programs link it next to libncursesw. The .pc files name only the
  # libraries: configure otherwise copies the build's LDFLAGS into them.
  pkg_autotools "${src_dir}/configure" \
    --mandir="${prefix}/share/man" \
    --with-terminfo-dirs="/etc/terminfo:${prefix}/share/terminfo:/usr/share/terminfo" \
    --with-manpage-format=normal \
    --with-shared \
    --with-termlib=tinfo \
    --without-debug \
    --without-normal \
    --with-cxx-shared \
    --enable-pc-files \
    --disable-pkg-ldflags \
    --with-pkg-config-libdir="${prefix}/lib/pkgconfig"
  # The terminfo functions (tgetent, tputs, ...) are in libtinfo now, and
  # ld resolves a program's symbols only from the libraries it names, not
  # from what those need. libncursesw.so, which -lncursesw finds, becomes a
  # linker script naming both, so builds that link only -lncursesw
  # (readline) still link.
  rm "${dest_dir}${prefix}/lib/libncursesw.so"
  echo "INPUT(libncursesw.so.6 -ltinfo)" >"${dest_dir}${prefix}/lib/libncursesw.so"
}
