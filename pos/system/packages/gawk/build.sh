pkg() {
  # awk is gawk on POS (BUILD.md "System stage"). -M uses gmp and mpfr
  # from core-libs.
  pkg_autotools

  rm -f "${dest_dir}${prefix}/bin/gawkbug" \
        "${dest_dir}${prefix}/share/man/man1/gawkbug.1"
}
