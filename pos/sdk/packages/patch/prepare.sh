# gnulib bootstrap: translations are fetched, then the build system is
# generated against src/gnulib.

prep() {
  prep_version
  prep_pull
  prep_gen
}
