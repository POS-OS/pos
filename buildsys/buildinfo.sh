#!/usr/bin/env bash
# What names a build's artifacts, from its info (work/builds/<id>/info),
# where the build recorded its version (release.sh: version_info). Sourced
# by the scripts that make or use them, with the build directory.
# BUILD.md "Build numbers".

# The value of a key in the info of the build in directory $1.
# Inputs:
#   $1    build directory ($bdir)
#   $2    info field key
info_get() {
  awk -v k="$2" '$1 == k {print $2}' "$1/info"
}

# Exit unless the build recorded a version. Builds made before VERSION had
# a product version have none, and their artifacts no names.
# Inputs:
#   $1    build directory ($bdir)
build_versioned() {
  [[ -n $(info_get "$1" product-version) ]] || {
    echo "build $(basename "$1") has no product version (made before VERSION had one); start another with ./build run --new" >&2
    exit 1
  }
}

# The build's version as one string, for the OS and the tag:
# <product version>.<build>.<revision>.<product release>
# (1.0.3.0.main.20261017-1524).
# Inputs:
#   $1    build directory ($bdir)
build_identifier() {
  build_versioned "$1"
  echo "$(info_get "$1" product-version).$(info_get "$1" build-number).$(info_get "$1" revision).$(info_get "$1" product-release)"
}

# The part of artifact names that names the build, and the name of its
# release: <major>.<minor>-<build>.<product release>
# (pos-system-1.0-3.main.20261017-1524.tar.zst).
# Inputs:
#   $1    build directory ($bdir)
build_stem() {
  build_versioned "$1"
  echo "$(info_get "$1" product-version)-$(info_get "$1" build-number).$(info_get "$1" product-release)"
}

# The OS build: <build>.<revision> (3.0).
# Inputs:
#   $1    build directory ($bdir)
os_build() {
  build_versioned "$1"
  echo "$(info_get "$1" build-number).$(info_get "$1" revision)"
}

# The version-release of the build's RPM packages: <major>.<minor>.0 as
# the version, <rpm release>.<product release> as the release
# (1.0.0-1.main.202610171524). rpm allows no '-' in either, so the
# timestamp's is dropped. Updates sort by the rpm release first (VERSION:
# RPM_RELEASE), then the product release.
# Inputs:
#   $1    build directory ($bdir)
rpm_evr() {
  local rel
  build_versioned "$1"
  rel=$(info_get "$1" product-release)
  echo "$(info_get "$1" product-version).0-$(info_get "$1" rpm-release).${rel//-/}"
}
