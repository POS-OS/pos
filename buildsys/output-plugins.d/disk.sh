#!/usr/bin/env bash
# Bootable disks for outputs (buildsys/outputs.sh), made from the tree of
# fs.sh, and their check in a VM. BUILD.md "Disks".

# Make the tree a bootable disk, pos-<output>-<stem>.qcow2: the tree's
# systemd-boot installed into /boot, and the partitions of repart.d made
# by systemd-repart, without loop devices. Its partitions have the
# discoverable partition types: systemd finds the ESP and root by their
# type, so the image needs no fstab and no root= on the kernel command
# line. /boot is the ESP: the boot loader entries and kernels are written
# there (fs_kernel, fs_dnf). The disk is compressed, for qemu, libvirt
# and the rest to boot or convert. Runs in output().
# Inputs:
#   $1    repart.d directory (outputs/<output>/repart.d)
#   work
disk_make() {
  local root=$work/root disk
  disk=$(output_file qcow2)
  # The tree's bootctl, run through its loader (as fs_sysusers), so /pos
  # need not be installed where this runs. /boot is not a vfat file system
  # here, as the ESP is when the system runs.
  SYSTEMD_RELAX_ESP_CHECKS=1 "$root/pos/lib/ld-linux-x86-64.so.2" \
    --library-path "$root/pos/lib:$root/pos/lib/systemd" \
    "$root/pos/bin/bootctl" --root="$root" --esp-path=/boot install --no-variables
  # systemd-repart writes a raw disk, which is then converted.
  rm -f "$work/disk.raw" "$disk.tmp"
  systemd-repart --empty=create --size=auto --offline=yes --dry-run=no \
    --root="$root" --definitions="$1" "$work/disk.raw"
  qemu-img convert -c -O qcow2 "$work/disk.raw" "$disk.tmp"
  rm "$work/disk.raw"
  mv "$disk.tmp" "$disk"
  echo "$disk"
}

# Check the disk: devtools/vm.sh boots it and runs a script in it as root
# (BUILD.md "Build numbers"). With --no-checks (CHECKS no) the check is
# skipped and the output recorded unchecked. Runs in output_host().
# Inputs:
#   $1        script, relative to the checkout (devtools/smoke.sh)
#   CHECKS, id
# Outputs:
#   OUTPUT_STATUS    unchecked when skipped
disk_check() {
  if [[ $CHECKS == no ]]; then
    OUTPUT_STATUS=unchecked
    return 0
  fi
  title "check $output"
  "$base/devtools/vm.sh" -o "$output" -c "$base/$1" "$id" ||
    die "$output: its check $1 failed (--no-checks skips it)"
}
