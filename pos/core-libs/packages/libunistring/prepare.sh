# autopull.sh takes gnulib from pos/common/src/gnulib; autogen.sh generates the build
# system.

prep() {
  prep_version
  prep_pull
  prep_gen
}
