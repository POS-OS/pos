# The git tree has no configure or help text; Makefile.aut generates
# them (autoconf, and nroff for the help text).

prep() {
  make -f Makefile.aut distfiles
}
