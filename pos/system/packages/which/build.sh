# GNU which. which's own xmalloc is used: --disable-iberty would leave it
# undefined, so the libiberty check is answered instead.

pkg() {
  pkg_autotools ac_cv_lib_iberty_xmalloc=no
}
