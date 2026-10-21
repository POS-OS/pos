# The Makefile asks git describe for the version, which a synced tree
# cannot answer: the build passes the snapshot name.

prep() {
  prep_version
}
