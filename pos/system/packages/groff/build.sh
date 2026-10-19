pkg() {
  # groff formats man pages for man-db (nroff, troff, tbl, eqn). No X11
  # previewers and no formatted documentation.
  pkg_autotools --without-x --with-doc=no
}
