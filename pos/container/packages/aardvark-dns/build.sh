pkg() {
  # The DNS server of podman's networks: containers on a network find each
  # other by name. Installed in /pos/libexec/podman, as netavark, which
  # starts it.
  pkg_cargo
  install -D -m 0755 "$cargo_out"/aardvark-dns "${dest_dir}${prefix}/libexec/podman/aardvark-dns"
}
