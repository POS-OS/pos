pkg() {
  pkg_sync_src

  # pam_cap is built with Linux-PAM later.
  pkg_compile prefix="$prefix" lib=lib GOLANG=no PAM_CAP=no
  pkg_install prefix="$prefix" lib=lib GOLANG=no PAM_CAP=no
}
