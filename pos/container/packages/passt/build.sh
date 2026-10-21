pkg() {
  # pasta: podman's default network for rootless containers (passt is the
  # same program for VMs). Its Makefile has no configure; the paths and the
  # version are make variables. No AppArmor or SELinux profiles.
  pkg_sync_src
  local -a vars=(prefix="$prefix" VERSION="$(<.tarball-version)")
  pkg_compile "${vars[@]}"
  pkg_install "${vars[@]}"
}
