pkg() {
  # bash is /bin/sh on POS (BUILD.md "System stage"). Link the readline built
  # in core-libs instead of the bundled copy.
  pkg_autotools --without-bash-malloc --with-installed-readline

  ln -sfn bash "${dest_dir}${prefix}/bin/sh"
  rm -f "${dest_dir}${prefix}/bin/bashbug" \
        "${dest_dir}${prefix}/share/man/man1/bashbug.1"
}
