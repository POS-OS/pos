pkg() {
  pkg_autotools
  rm -f "${dest_dir}${prefix}/lib/libz.a"
}
