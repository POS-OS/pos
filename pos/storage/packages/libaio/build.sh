pkg() {
  # The Linux AIO library, for lvm2's tools. Its own Makefile; shared only
  # (the static archive is removed).
  pkg_sync_src
  pkg_compile prefix="$prefix" libdir="${prefix}/lib"
  pkg_install prefix="$prefix" libdir="${prefix}/lib"
  rm "${dest_dir}${prefix}/lib/libaio.a"
}
