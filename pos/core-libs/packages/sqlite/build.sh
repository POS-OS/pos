pkg() {
  # --soname=legacy: libsqlite3.so.0, as releases before autosetup and
  # Fedora have. Without it the library has no soname, and programs linked
  # to it record the development link libsqlite3.so.
  pkg_autotools --disable-static --enable-fts5 --soname=legacy
}
