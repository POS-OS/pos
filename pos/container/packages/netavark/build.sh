pkg() {
  # podman's network backend: bridges, veth pairs and nftables rules for
  # rootful containers, and the DHCP proxy for macvlan. Installed in
  # /pos/libexec/podman, which containers.conf names as podman's helper
  # directory, with the man pages and the units (the DHCP proxy socket,
  # rule reloads).
  pkg_cargo
  local -a vars=(PREFIX="$prefix" LIBEXECDIR="${prefix}/libexec" SYSTEMDDIR="${prefix}/lib/systemd/system")
  install -D -m 0755 "$cargo_out"/netavark "${dest_dir}${prefix}/libexec/podman/netavark"
  make -C docs "${vars[@]}" DESTDIR="$dest_dir" install
  make "${vars[@]}" DESTDIR="$dest_dir" SELINUXOPT= install.systemd
}
