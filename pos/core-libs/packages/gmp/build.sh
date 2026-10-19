pkg() {
  # --enable-fat: gmp otherwise tunes for the build machine's CPU, and the
  # archive is installed on other machines. --enable-cxx needs libstdc++ from
  # gcc-runtime in /pos.
  pkg_autotools \
    --disable-static \
    --enable-cxx \
    --enable-fat
}
