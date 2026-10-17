# The build's pos, pos-sdk and pos-fedora packages, and dnf, so Fedora
# packages install on top and use POS for what it has.
output() {
  fs_dnf pos pos-sdk pos-fedora dnf
  fs_factory
  fs_archive
}
