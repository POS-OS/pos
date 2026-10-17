# The OS stages, Fedora's kernel, systemd-boot and the partitions of
# repart.d. root/ is the configuration of the kernel's installation
# (/etc/kernel) and the network; vm-disk-dnf uses it and repart.d too.
output() {
  fs_stages
  fs_layout "$(output_dir)/layout"
  fs_copy "$(output_dir)/root"
  fs_factory
  fs_sysusers
  # POS boots kernels other projects build.
  fs_kernel kernel-core kernel-modules-core kernel-modules
  disk_make "$(output_dir)/repart.d"
}

output_host() {
  disk_check devtools/smoke.sh
}
