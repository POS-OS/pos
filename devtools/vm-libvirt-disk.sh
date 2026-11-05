#!/usr/bin/env bash
# Puts the disk of a published release, set up as a test system, into
# libvirt's images, as the base pos-vm-disk-<product version>.qcow2, and
# makes the disk a libvirt VM boots, pos-rootfs.qcow2, a new overlay of 12G
# on top of it:
#
#   vm-libvirt-disk.sh [-o <output>] [-t <timezone>] [-u <user>] <build>
#     <build>      the release's BUILD number, 7 for 1.0-7.main.20261025-1813
#     -o <output>  the disk's output: vm-disk (default) or vm-disk-dnf
#     -t <zone>    the time zone (default: this machine's)
#     -u <user>    the user to add (default: $USER); -u '' adds none
#
# It asks for the passwords of root and the user. The setup is
# devtools/vm-setup.sh, run once in the disk by devtools/vm.sh before libvirt
# boots it: first boot's settings (time zone, root password), the container
# stage, the apps of the newest pos-sdk and pos-extras releases that have an
# app archive, and the user. The disk is set up in work/vm-libvirt, a copy
# of the release's (reflinked where the file system can), removed once it
# is in libvirt's images. The disk needs pos-app (pos-integration) and the
# /usr/share/zoneinfo link: releases after 1.0-9.
#
# Both are replaced on every run, so the overlay never outlives its base;
# what the VM wrote is gone. Shut the VM down first. Runs on the host
# (sudo writes libvirt's images).

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../buildsys/buildinfo.sh
source "$base/buildsys/buildinfo.sh"
source "$base/buildsys/config.sh"
source "$base/buildsys/release.sh"
store=$(config release-dir)
pv=$(version_field HEAD PRODUCT_VERSION)
images=/var/lib/libvirt/images
rootfs=$images/pos-rootfs.qcow2
work=$base/work/vm-libvirt

output=vm-disk
timezone=$(readlink -f /etc/localtime | sed -n 's|.*/zoneinfo/||p')
user=${USER:-}
while (($#)); do
  case $1 in
    -o) output=${2:?}; shift 2 ;;
    -t) timezone=${2:?}; shift 2 ;;
    -u) user=$2; shift 2 ;;
    *) break ;;
  esac
done
build=${1:?usage: vm-libvirt-disk.sh [-o <output>] [-t <timezone>] [-u <user>] <build>}
[[ -n $timezone ]] || { echo "no time zone: give -t <timezone>" >&2; exit 1; }

# The release of that build number, from the project's release library.
releases=("$store/$project/$pv-$build".*)
[[ -d ${releases[0]} && ${#releases[@]} -eq 1 ]] || {
  echo "no single release $pv-$build in $store/$project" >&2
  exit 1
}
release=${releases[0]}
disk=$release/pos-$output-$(basename "$release").qcow2
[[ -f $disk ]] || { echo "no disk $disk" >&2; exit 1; }

# The app archive of the newest release of an app project that has one.
# Inputs:
#   $1    the project (pos-sdk, pos-extras)
# Output: the archive's path, or nothing when no release has one.
app_archive() {
  local dir archives
  while read -r dir; do
    archives=("$store/$1/$dir"/*-app-*.tar.zst)
    if [[ -f ${archives[0]} ]]; then
      echo "${archives[0]}"
      return
    fi
  done < <(ls "$store/$1" 2>/dev/null | sort -rV)
}

# A password read twice from the terminal, hashed (SHA-512 crypt).
# Inputs:
#   $1    whose, for the prompt
# Output: the hash.
password_hash() {
  local first second
  while :; do
    read -rsp "password of $1: " first </dev/tty; echo >/dev/tty
    read -rsp "again: " second </dev/tty; echo >/dev/tty
    [[ -n $first && $first == "$second" ]] && break
    echo "empty, or not the same; again" >/dev/tty
  done
  openssl passwd -6 -stdin <<<"$first"
}

root_hash=$(password_hash root)
user_hash=
[[ -z $user ]] || user_hash=$(password_hash "$user")

# The disk to set up, the apps to share with it, and the setup script with
# its settings in front; the script holds the hashes, so it goes at exit.
rm -rf "$work"
mkdir -p "$work/apps"
trap 'rm -f "$work/setup.sh"' EXIT
setup=$work/pos-$output-$pv.qcow2
cp --reflink=auto "$disk" "$setup"
for app in pos-sdk pos-extras; do
  archive=$(app_archive "$app")
  if [[ -n $archive ]]; then
    echo "app $archive"
    cp --reflink=auto "$archive" "$work/apps/"
  else
    echo "no $app release has an app archive"
  fi
done
(
  umask 077
  printf 'TIMEZONE=%q\nROOT_HASH=%q\nUSER_NAME=%q\nUSER_HASH=%q\n' \
    "$timezone" "$root_hash" "$user" "$user_hash"
  cat "$base/devtools/vm-setup.sh"
) >"$work/setup.sh"
"$base/devtools/vm.sh" -d "$setup" -w -s "$work/apps" -c "$work/setup.sh"

# The base, then a new overlay on it: writes go there, the base stays as set up.
target=$images/pos-vm-disk-$pv.qcow2
sudo cp "$setup" "$target"
sudo rm -f "$rootfs"
sudo qemu-img create -q -f qcow2 -b "$target" -F qcow2 "$rootfs" 12G
echo "$rootfs on $target"
rm -rf "$work"
