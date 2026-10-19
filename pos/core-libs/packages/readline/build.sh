pkg() {
  pkg_configure \
    --disable-static \
    --with-curses \
    --docdir="${prefix}/share/doc/readline"
  pkg_compile SHLIB_LIBS="-lncursesw"
  pkg_install SHLIB_LIBS="-lncursesw"
}
