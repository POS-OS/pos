# autoreconf generates the build system. Not bootstrap: it makes autoconf's
# warnings errors, which a newer autoconf than upstream's can trip.

prep() {
  mkdir -p config
  autoreconf -fi
}
