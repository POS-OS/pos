pkg() {
  pkg_sync_src

  pkg_compile prefix="$prefix"
  pkg_install prefix="$prefix"
  rm -f "${dest_dir}${prefix}/lib/libzstd.a"
}
