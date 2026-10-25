# autoreconf generates the build system. Not autogen.sh: it runs the same
# tools after checking the automake version against those upstream tested.

prep() {
  autoreconf -fi
}
