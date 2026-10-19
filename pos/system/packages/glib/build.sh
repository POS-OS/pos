pkg() {
  # Built from git: gvdb is a submodule in the tree, so no subproject is
  # downloaded. GObject introspection, the documentation, the tests and
  # sysprof are off; GIO uses util-linux's libmount.
  pkg_meson \
        --wrap-mode=nodownload \
        -Dintrospection=disabled \
        -Ddocumentation=false \
        -Dman-pages=disabled \
        -Dtests=false \
        -Dinstalled_tests=false \
        -Dsysprof=disabled \
        -Dselinux=disabled \
        -Dlibelf=disabled \
        -Dlibmount=enabled
  # The code generators are Python programs, and POS has no Python
  # (programs in /pos depend on nothing outside it). They are build tools
  # for GLib-based projects, which take them from the build host for now.
  rm -f "${dest_dir}${prefix}"/bin/{gdbus-codegen,glib-genmarshal,glib-mkenums,gtester-report}
  rm -rf "${dest_dir}${prefix}/share/glib-2.0/codegen"
}
