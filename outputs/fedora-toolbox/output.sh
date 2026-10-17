# containerfile on top of container-fs-dnf, in the podman of the host.
output_host() {
  podman_build container-fs-dnf
}
