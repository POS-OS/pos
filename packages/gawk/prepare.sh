# gawk carries its own gnulib subset and generated files; bootstrap.sh
# only fixes timestamps so configure is not regenerated. The build copies
# the prepared tree with its timestamps.

prep() {
  ./bootstrap.sh
}
