pkg() {
  if [[ -f $src_dir/meson.build ]]; then
    pkg_meson
  elif [[ -f $src_dir/Makefile-libbz2_so ]]; then
    pkg_sync_src
    make -f Makefile-libbz2_so
    make clean
    pkg_compile
    make PREFIX="${dest_dir}${prefix}" install
    mkdir -p "${dest_dir}${prefix}/lib"
    cp -a libbz2.so.* "${dest_dir}${prefix}/lib/"
  else
    echo "unrecognized bzip2 build system" >&2
    exit 1
  fi
}
