pkg() {
  # Go from the toolchain reference (build-requires go), with the modules of
  # podman's committed vendor directory (pkg_go_env). Build tags as
  # Fedora's, set here rather than probed by hack/*_tag.sh: seccomp,
  # systemd, sqlite from POS (libsqlite3), libsubid; signatures with Go's
  # OpenPGP (no GPGME); no btrfs or AppArmor.
  #
  # The vendor configuration directory, /usr/share/containers in podman's
  # libraries, is /pos/share/containers (containers-common); /etc/containers
  # stays the machine's. The units and the quadlet generators go to
  # /pos/lib/systemd, where POS's systemd reads them.
  #
  # The man pages are made with Fedora's go-md2man; -o skips
  # .install.md2man, which builds podman's copy from test/tools, not in the
  # synced source.
  #
  # podman-remote is the client of a podman service (podman system
  # service, or podman.socket), here or on another machine, built with
  # podman's remote tags. docker is podman's Docker CLI emulation: a script
  # that runs podman, the docker man pages (links to podman's), a
  # profile.d file pointing DOCKER_HOST at podman's socket, and a
  # tmpfiles.d link from /run/docker.sock to it, for the system and for
  # each user's runtime directory.
  pkg_sync_src
  pkg_go_env
  local -a vars=(
    PREFIX="$prefix"
    ETCDIR="$sysconfdir"
    LIBDIR="${prefix}/lib"
    LIBEXECDIR="${prefix}/libexec"
    HELPER_BINARIES_DIR="${prefix}/libexec/podman"
    GOMD2MAN=go-md2man
    -o .install.md2man
    SELINUXOPT=
    BUILDTAGS="grpcnotrace seccomp systemd libsqlite3 libsubid containers_image_openpgp exclude_graphdriver_btrfs"
    EXTRA_LDFLAGS="-linkmode=external -X go.podman.io/storage/pkg/configfile.systemConfigPath=${prefix}/share/containers -X go.podman.io/common/pkg/subscriptions.DefaultMountsFile=${prefix}/share/containers/mounts.conf"
  )
  pkg_compile "${vars[@]}" podman podman-remote rootlessport quadlet docs
  make "${vars[@]}" docker-docs
  make DESTDIR="$dest_dir" "${vars[@]}" install.bin install.remote install.man install.systemd \
    install.completions install.docker-full
}
