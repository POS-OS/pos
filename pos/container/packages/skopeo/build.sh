pkg() {
  # Go from the toolchain reference (build-requires go), with the modules of
  # skopeo's committed vendor directory (pkg_go_env). The build tags are
  # podman's storage and signature tags (pos/container/packages/podman),
  # set here rather than probed by hack/*_tag.sh. The vendor configuration
  # directory is /pos/share/containers, as podman's.
  #
  # Not make install: it installs policy.json and the registries.d default
  # into /etc/containers, which containers-common has in
  # /pos/share/containers.
  pkg_sync_src
  pkg_go_env
  local -a vars=(
    PREFIX="$prefix"
    GOMD2MAN=go-md2man
    BUILDTAGS="libsqlite3 libsubid containers_image_openpgp exclude_graphdriver_btrfs"
    EXTRA_LDFLAGS="-linkmode=external -X go.podman.io/storage/pkg/configfile.systemConfigPath=${prefix}/share/containers"
  )
  pkg_compile "${vars[@]}" bin/skopeo docs
  make DESTDIR="$dest_dir" "${vars[@]}" install-binary install-docs install-completions
}
