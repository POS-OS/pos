#!/usr/bin/env bash
# Makes the toolbox image of a published release in podman: the release's
# container-fs-dnf archive imported, and outputs/fedora-toolbox/containerfile
# of this checkout built on it, as ./build makes it for a build (BUILD.md
# "Images made with podman"). The image is tagged with the release and
# with its product version, which moves to the release made last:
#
#   release-toolbox.sh <release>     (a directory in release-dir, or its path)
#   toolbox create -i localhost/pos-fedora-toolbox:<product version>
#
# Runs on the host or in a toolbox, where podman is the host's (through
# flatpak-spawn, as ./build does).

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../buildsys/buildinfo.sh
source "$base/buildsys/buildinfo.sh"
# shellcheck source=../buildsys/config.sh
source "$base/buildsys/config.sh"

podman() {
  if [[ -f /run/.toolboxenv ]]; then
    flatpak-spawn --host podman "$@"
  else
    command podman "$@"
  fi
}

# Paths as the host sees them, for podman.
host_path() {
  local p
  p=$(realpath "$1")
  echo "${p#/run/host}"
}

# The value of a key in an output's meta.
meta() {
  sed -e 's/#.*//' "$base/outputs/$1/meta" | awk -v k="$2" '$1 == k {print $2}'
}

release=${1:?usage: release-toolbox.sh <release>}
[[ -d $release ]] || release=$(config release-dir)/$release
[[ -f $release/info ]] || { echo "no release $release" >&2; exit 1; }
name=$(build_stem "$release")
version=$(info_get "$release" product-version)
archive=$release/pos-container-fs-dnf-$name.tar.zst
[[ -f $archive ]] || { echo "release $name has no container-fs-dnf image ($archive)" >&2; exit 1; }

from=localhost/$(meta container-fs-dnf tag):$name
to=localhost/$(meta fedora-toolbox tag)
path=/usr/local/bin:/usr/bin:/pos/bin:/pos/sbin
[[ $(meta container-fs-dnf path-priority) != pos ]] || path=/pos/bin:/pos/sbin:/usr/local/bin:/usr/bin
podman import --change "ENV PATH=$path" \
  --change 'CMD ["/usr/bin/bash"]' \
  --change "LABEL pos.build=$(info_get "$release" id)" --change "LABEL pos.version=$(build_identifier "$release")" \
  "$(host_path "$archive")" "$from"
podman build --build-arg "BASE=$from" \
  --label "pos.build=$(info_get "$release" id)" --label "pos.version=$(build_identifier "$release")" \
  -t "$to:$name" -f "$(host_path "$base/outputs/fedora-toolbox/containerfile")" \
  "$(host_path "$base/outputs/fedora-toolbox")"
podman tag "$to:$name" "$to:$version"
echo "$to:$version is release $name"
