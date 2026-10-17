#!/usr/bin/env bash
# Makes an image a build made available in podman, tagged with the build ID
# and with its product version (1.0), the tag to make containers and
# toolboxes from. The version tag moves to whichever build of that version
# was made available last. A build tags the images it makes with podman
# itself; this imports the others, or moves the version tag back to an
# earlier build:
#
#   import-image.sh [-o <output>] [<id>]   (default: container-fs, the current build)
#   toolbox create -i localhost/pos-fedora-toolbox:<product version>
#
# An output's name in podman is the tag in outputs/<output>/meta
# (container-fs: pos, container-fs-dnf: pos-dnf). One with an archive
# (pos-<output>-<stem>.tar.zst) is imported from it. One made with podman
# (containerfile) is in podman since the build made it, and is only tagged.

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../buildsys/buildinfo.sh
source "$base/buildsys/buildinfo.sh"
builds=${base}/work/builds

# The host's podman, from a toolbox too (as ./build).
podman() {
  if [[ -f /run/.toolboxenv ]]; then
    flatpak-spawn --host podman "$@"
  else
    command podman "$@"
  fi
}

# The value of a key in the output's meta.
meta() {
  sed -e 's/#.*//' "$base/outputs/$output/meta" | awk -v k="$1" '$1 == k {print $2}'
}

output=container-fs
if [[ ${1:-} == -o ]]; then
  output=${2:?}
  shift 2
fi
id=${1:-$(basename "$(readlink "${builds}/current")")}
bdir=${builds}/${id}
[[ -f $bdir/info ]] || { echo "no build $id" >&2; exit 1; }
[[ -f $base/outputs/$output/meta ]] || { echo "not an output: $output" >&2; exit 1; }
version=$(info_get "$bdir" product-version)
[[ -n $version ]] || { echo "build $id has no product version (made before VERSION had one)" >&2; exit 1; }
name=$(meta tag)
[[ -n $name ]] || { echo "$output has no name in podman (meta: tag)" >&2; exit 1; }

# POS programs are in /pos/bin and /pos/sbin. Fedora layouts (path-priority
# host) link most of them into /usr/bin, except where a Fedora package has
# the path, so /usr/bin comes first there.
path=/usr/local/bin:/usr/bin:/pos/bin:/pos/sbin
[[ $(meta path-priority) != pos ]] || path=/pos/bin:/pos/sbin:/usr/local/bin:/usr/bin

if [[ -f $base/outputs/$output/containerfile ]]; then
  podman image exists "localhost/${name}:${id}" || {
    echo "build $id has no $output image in podman; make it with ./build output $output" >&2
    exit 1
  }
else
  archive=${bdir}/pos-${output}-$(build_stem "$bdir").tar.zst
  [[ -f $archive ]] || { echo "build $id has no $output image ($archive)" >&2; exit 1; }
  # As the host sees it: work may be a link, the checkout under /run/host.
  archive=$(realpath "$archive")
  podman import --change "ENV PATH=$path" \
    --change 'CMD ["/usr/bin/bash"]' \
    --change "LABEL pos.build=$id" --change "LABEL pos.version=$(build_identifier "$bdir")" \
    "${archive#/run/host}" "localhost/${name}:${id}"
fi
podman tag "localhost/${name}:${id}" "localhost/${name}:${version}"
echo "localhost/${name}:${version} is build $id"
