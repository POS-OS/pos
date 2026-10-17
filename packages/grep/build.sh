pkg() {
  # grep -P uses the pcre2 from core-libs.
  pkg_autotools --enable-perl-regexp
}
