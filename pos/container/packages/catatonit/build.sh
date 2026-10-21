pkg() {
  # The init of podman's pods and of podman run --init: reaps zombies and
  # forwards signals. Installed in /pos/bin, which containers.conf names.
  pkg_autotools
}
