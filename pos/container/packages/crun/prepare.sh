# autoreconf generates the build system, crun's and its libocispec
# submodule's. Not autogen.sh: it updates the submodules with git, and the
# synced tree has them already. The version is a snapshot name
# (git-version-gen reads .tarball-version).

prep() {
  prep_version
  autoreconf -fi
}
