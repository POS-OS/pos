#!/usr/bin/env bash
# Puts the vm-disk-dnf disk of a published release into libvirt's images,
# as the base pos-vm-disk-<product version>.qcow2, and makes the disk a
# libvirt VM boots, pos-rootfs.qcow2, a new overlay of 12G on top of it:
#
#   vm-libvirt-disk.sh <build>    (<build>: the release's BUILD number, 7
#                                  for 1.0-7.main.20261025-1813)
#
# Both are replaced on every run, so the overlay never outlives its base;
# what the VM wrote is gone. Shut the VM down first.

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../buildsys/buildinfo.sh
source "$base/buildsys/buildinfo.sh"
source "$base/buildsys/config.sh"
source "$base/buildsys/release.sh"
store=$(config release-dir)
pv=$(version_field HEAD PRODUCT_VERSION)
build=${1:?usage: vm-libvirt-disk.sh <build>}
images=/var/lib/libvirt/images
rootfs=$images/pos-rootfs.qcow2

# The release of that build number, from the project's release library.
releases=("$store/$project/$pv-$build".*)
[[ -d ${releases[0]} && ${#releases[@]} -eq 1 ]] || {
  echo "no single release $pv-$build in $store/$project" >&2
  exit 1
}
release=${releases[0]}
disk=$release/pos-vm-disk-dnf-$(basename "$release").qcow2
[[ -f $disk ]] || { echo "no disk $disk" >&2; exit 1; }

# The base, then a new overlay on it: writes go there, the base stays as published.
target=$images/pos-vm-disk-$pv.qcow2
sudo cp "$disk" "$target"
sudo rm -f "$rootfs"
sudo qemu-img create -q -f qcow2 -b "$target" -F qcow2 "$rootfs" 12G
echo "$rootfs on $target"
