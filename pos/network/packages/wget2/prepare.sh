# gnulib bootstrap: translations are fetched, then the build system is
# generated against pos/common/src/gnulib. Its post-pull hook clones the
# wiki submodule only with git, which bootstrap here runs without.

prep() {
  prep_version
  prep_pull
  prep_gen
}
