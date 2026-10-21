pkg() {
  # What Fedora's containers-common has, in /pos/share/containers: the
  # defaults of containers.conf, storage.conf, registries.conf and
  # policy.json, seccomp.json, and the registries.d default. podman reads
  # them there (its build sets the vendor directory, pos/container/packages/podman)
  # and /etc/containers overrides them. POS's settings are drop-ins of the
  # same directory, 00-pos.conf: where the helpers are, crun, the overlay
  # driver, docker.io for short names. No RHEL subscription mounts or Red
  # Hat signing keys.
  local share=${dest_dir}${prefix}/share/containers man5=${dest_dir}${prefix}/share/man/man5 f
  install -D -m 0644 "$src_dir/common/pkg/config/containers.conf" "$share/containers.conf"
  install -D -m 0644 "$src_dir/common/pkg/seccomp/seccomp.json" "$share/seccomp.json"
  install -D -m 0644 "$src_dir/storage/storage.conf" "$share/storage.conf"
  install -D -m 0644 "$src_dir/image/registries.conf" "$share/registries.conf"
  install -D -m 0644 "$src_dir/image/default-policy.json" "$share/policy.json"
  install -D -m 0644 "$src_dir/image/default.yaml" "$share/registries.d/default.yaml"
  install -D -m 0644 "$recipe_dir/containers.conf" "$share/containers.conf.d/00-pos.conf"
  install -D -m 0644 "$recipe_dir/storage.conf" "$share/storage.conf.d/00-pos.conf"
  install -D -m 0644 "$recipe_dir/registries.conf" "$share/registries.conf.d/00-pos.conf"
  # /etc/containers holds the machine's own: its drop-in directories.
  install -d "${dest_dir}${sysconfdir}/containers"/{containers.conf.d,storage.conf.d,registries.conf.d,registries.d,certs.d,oci/hooks.d,networks,systemd}

  install -d "$man5"
  for f in "$src_dir"/common/docs/*.5.md "$src_dir"/image/docs/*.5.md "$src_dir/storage/docs/containers-storage.conf.5.md"; do
    go-md2man -in "$f" -out "$man5/$(basename "${f%.md}")"
  done
  install -m 0644 "$src_dir/image/docs/containers-registries.conf.d.5" "$man5/"
}
