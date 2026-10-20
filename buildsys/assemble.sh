#!/usr/bin/env bash
# Assemble a stage of a build into one archive. Run by buildsys/build.sh.
#
#   assemble.sh <build dir> <stage> [<reference dir>]
#
# A package the build did not build is taken from its reference: a pos
# build takes the toolchain packages from it. The archive is
# <build dir>/pos-<stage>-<stem>.tar.zst (buildinfo.sh) with a top-level
# pos/ directory. The merged tree is left at <build dir>/assemble/<stage>/pos.
# The packages' separate debug info (pkg_strip in buildsys/pkg.sh) is
# archived the same way as <build dir>/pos-debug-<stage>-<stem>.tar.zst,
# merged at <build dir>/assemble-debug/<stage>/pos; it extracts on top of
# the stage, into /pos/lib/debug. The stage with /pos/lib/os-release
# gets the build's version in it.

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=buildinfo.sh
source "$base/buildsys/buildinfo.sh"
bdir=${1:-}
stage=${2:-}
rdir=${3:-}

if [[ -z $bdir || -z $stage ]]; then
  echo "usage: $0 <build dir> <stage> [<reference dir>]" >&2
  exit 1
fi

list=${base}/pos/${stage}/stage
if [[ ! -f $list ]]; then
  echo "unknown stage: $stage (missing $list)" >&2
  exit 1
fi

stem=$(build_stem "$bdir")
root=${bdir}/assemble/${stage}
archive=${bdir}/pos-${stage}-${stem}.tar.zst
droot=${bdir}/assemble-debug/${stage}
darchive=${bdir}/pos-debug-${stage}-${stem}.tar.zst

rm -rf "$root" "$droot" "$darchive"
mkdir -p "$root/pos" "$droot/pos"

while read -r package; do
  package=${package%%#*}
  package=${package//[[:space:]]/}
  [[ -z $package ]] && continue
  from=$bdir
  if [[ ! -f ${from}/dest/${package}/pos/lib/pos/packages/${package}/meta ]]; then
    from=$rdir
    if [[ -z $from || ! -f ${from}/dest/${package}/pos/lib/pos/packages/${package}/meta ]]; then
      echo "${package} is not built in $bdir or its reference" >&2
      exit 1
    fi
  fi
  rsync -a "${from}/dest/${package}/pos/" "$root/pos/"
  if [[ -d ${from}/debug/${package}/pos ]]; then
    rsync -a "${from}/debug/${package}/pos/" "$droot/pos/"
  fi
done < "$list"

# os-release names the build (os-release(5); BUILD.md "Build numbers"):
# PRETTY_NAME and VERSION_ID the product version, VERSION the product
# release, BUILD_ID the build's identifier and POS_BUILD the OS build,
# <build>.<revision>, which has no field of its own. RELEASE_TYPE is
# development for a <branch>.<timestamp> release, stable for a static
# one. SYSEXT_LEVEL is the build's identifier too: systemd-sysext merges
# only stage images of the same build (BUILD.md "Stage images"). NAME stays
# the package's, without a version. A copy, not the package's staging tree.
osrel=$root/pos/lib/os-release
if [[ -f $osrel ]]; then
  name=$(sed -n 's/^NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$osrel")
  sed -i -E '/^(PRETTY_NAME|VERSION|VERSION_ID|BUILD_ID|POS_BUILD|RELEASE_TYPE|SYSEXT_LEVEL)=/d' "$osrel"
  {
    echo "PRETTY_NAME=\"$name $(info_get "$bdir" product-version)\""
    echo "VERSION=\"$(info_get "$bdir" product-release)\""
    echo "VERSION_ID=$(info_get "$bdir" product-version)"
    echo "BUILD_ID=$(build_identifier "$bdir")"
    echo "POS_BUILD=$(os_build "$bdir")"
    echo "RELEASE_TYPE=$(info_get "$bdir" release-type)"
    echo "SYSEXT_LEVEL=$(build_identifier "$bdir")"
  } >>"$osrel"
fi

# Everything in /pos is owned by root. Recording 0:0 here is what makes the
# set-uid bits set by pkg_setuid effective once extracted as root.
tar --zstd --owner=0 --group=0 -cf "$archive" -C "$root" pos
echo "$archive"
if [[ -n $(find "$droot/pos" -mindepth 1 -print -quit) ]]; then
  tar --zstd --owner=0 --group=0 -cf "$darchive" -C "$droot" pos
  echo "$darchive"
fi
