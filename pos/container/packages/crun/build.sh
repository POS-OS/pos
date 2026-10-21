pkg() {
  # The OCI runtime podman runs containers with: cgroup v2 through
  # systemd and eBPF device rules, seccomp, capabilities. No CRIU
  # (checkpoint and restore), no Wasm or libkrun handlers, no Python or
  # Lua bindings; libcrun is not installed. BLAKE3 (layer digests) is the
  # embedded copy. crun.1 is committed.
  pkg_autotools \
    --disable-static \
    --enable-caps \
    --enable-seccomp \
    --enable-systemd \
    --enable-bpf \
    --disable-criu \
    --disable-libcrun \
    --enable-embedded-blake3 \
    --without-python-bindings \
    --without-lua-bindings
}
