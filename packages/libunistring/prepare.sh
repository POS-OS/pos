# autopull.sh takes gnulib from src/gnulib; autogen.sh generates the build
# system.

prep() {
  prep_version
  prep_pull
  prep_gen
}
