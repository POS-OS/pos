# The build's pos and pos-fedora packages, and dnf, so Fedora packages
# install on top and use POS for what it has. pos-sdk is a project of its
# own and makes no RPM yet.
output() {
  fs_dnf pos pos-fedora dnf
  fs_factory
  fs_archive
}
