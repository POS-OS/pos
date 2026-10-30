# container-fs-dnf's packages and Fedora's kernel, whose scriptlets install
# it with POS's kernel-install, configured by vm-disk's root/etc/kernel:
# POS's dracut makes the initramfs, the boot loader entry goes to /boot,
# which is the ESP when the system runs; the kernel's modules go through
# the layout's /usr/lib/modules link. The disk is vm-disk's.
output() {
  fs_layout "$(output_dir)/layout"
  fs_copy "$(output_dir vm-disk)/root"
  fs_dnf pos pos-fedora dnf kernel-core kernel-modules
  fs_factory
  disk_make "$(output_dir vm-disk)/repart.d"
}

output_host() {
  disk_check devtools/smoke.sh
}
