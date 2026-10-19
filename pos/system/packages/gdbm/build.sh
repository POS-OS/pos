pkg() {
  # libgdbm-compat is the ndbm/dbm API man-db can use.
  pkg_autotools --disable-static --enable-libgdbm-compat
}
