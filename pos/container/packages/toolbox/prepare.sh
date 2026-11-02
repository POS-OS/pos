# toolbox's Go modules (src/go.mod) are not committed: they are vendored,
# so the build runs offline.

prep() {
  prep_go_vendor src
}
