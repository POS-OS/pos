pkg() {
  # podman's container monitor: holds a container's terminal and logs
  # (journald through libsystemd) and reports its exit. Installed in
  # /pos/bin, which containers.conf names (pos/container/packages/containers-common).
  pkg_meson
}
