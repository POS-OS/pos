# container-fs-dnf's packages and Fedora's kernel, whose scriptlets install
# it with POS's kernel-install, configured by vm-disk's root/etc/kernel:
# POS's dracut makes the initramfs, the boot loader entry goes to /boot,
# which is the ESP when the system runs. The disk is vm-disk's.
output() {
  fs_copy "$(output_dir vm-disk)/root"
  fs_dnf pos pos-sdk pos-fedora dnf kernel-core kernel-modules
  fs_factory
  disk_make "$(output_dir vm-disk)/repart.d"
}

output_host() {
  disk_check devtools/smoke.sh
}
