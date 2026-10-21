pkg() {
  # Go from the build host (host-requires golang), with the modules of
  # podman's committed vendor directory (pkg_go_env). Build tags as
  # Fedora's, set here rather than probed by hack/*_tag.sh: seccomp,
  # systemd, sqlite from POS (libsqlite3), libsubid; signatures with Go's
  # OpenPGP (no GPGME); no btrfs or AppArmor.
  #
  # The vendor configuration directory, /usr/share/containers in podman's
  # libraries, is /pos/share/containers (containers-common); /etc/containers
  # stays the machine's. The units and the quadlet generators go to
  # /pos/lib/systemd, where POS's systemd reads them.
  pkg_sync_src
  pkg_go_env
  local -a vars=(
    PREFIX="$prefix"
    ETCDIR="$sysconfdir"
    LIBDIR="${prefix}/lib"
    LIBEXECDIR="${prefix}/libexec"
    HELPER_BINARIES_DIR="${prefix}/libexec/podman"
    GOMD2MAN=go-md2man
    SELINUXOPT=
    BUILDTAGS="grpcnotrace seccomp systemd libsqlite3 libsubid containers_image_openpgp exclude_graphdriver_btrfs"
    EXTRA_LDFLAGS="-linkmode=external -X go.podman.io/storage/pkg/configfile.systemConfigPath=${prefix}/share/containers -X go.podman.io/common/pkg/subscriptions.DefaultMountsFile=${prefix}/share/containers/mounts.conf"
  )
  pkg_compile "${vars[@]}" podman rootlessport quadlet docs
  # Not make install: it installs podman-remote too, which is not built.
  make DESTDIR="$dest_dir" "${vars[@]}" install.bin install.man install.systemd install.completions
}
