# autopull.sh takes gnulib from src/gnulib and clones the tree-sitter
# grammars gettext-tools uses; autogen.sh generates the build system for
# gettext-runtime and gettext-tools.

prep() {
  prep_version
  prep_pull
  prep_gen
  # Man pages depend on the top-level .version stamp. Only the top-level
  # configure writes it (gl_CONFIG_VERSION_STAMP), and the build configures
  # gettext-runtime alone.
  cp .tarball-version .version
}
