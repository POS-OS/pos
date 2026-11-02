pkg() {
  # Go from the build host (host-requires golang), with the modules of
  # buildah's committed vendor directory (pkg_go_env). The build tags are
  # podman's (pos/container/packages/podman), set here rather than probed
  # by hack/*_tag.sh. The vendor configuration directory is
  # /pos/share/containers, as podman's: both read containers-common's
  # defaults there.
  #
  # The man pages are made with Fedora's go-md2man; -o skips
  # install.go-md2man, which builds buildah's copy from tests/tools, not in
  # the synced source. Likewise the entrypoint of confidential workload
  # images (internal/mkcw/embed) is the committed one, not reassembled.
  pkg_sync_src
  pkg_go_env
  local -a vars=(
    PREFIX="$prefix"
    GOMD2MAN=go-md2man
    -o install.go-md2man
    -o internal/mkcw/embed/entrypoint_amd64.gz
    SELINUXOPT=
    TAGS="grpcnotrace seccomp systemd libsqlite3 libsubid containers_image_openpgp exclude_graphdriver_btrfs"
    EXTRA_LDFLAGS="-linkmode=external -X go.podman.io/storage/pkg/configfile.systemConfigPath=${prefix}/share/containers -X go.podman.io/common/pkg/subscriptions.DefaultMountsFile=${prefix}/share/containers/mounts.conf"
  )
  pkg_compile "${vars[@]}" bin/buildah docs
  make DESTDIR="$dest_dir" "${vars[@]}" install.nobuild install.completions
}
