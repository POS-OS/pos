# autogen.sh generates the build system; --no-po4a leaves out the
# translated man pages (po4a).

prep() {
  ./autogen.sh --no-po4a
}
