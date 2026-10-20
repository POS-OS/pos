pkg() {
  # Its own configure, which detects libraries with pkg-config, and a
  # Makefile that takes the paths as variables. Programs in /pos/sbin, as
  # Fedora's /usr/sbin; the default tables (rt_tables, rt_protos, ...) in
  # /pos/share/iproute2, which /etc/iproute2 overrides per file. No libbpf
  # (tc's loader uses libelf), no Berkeley DB (no arpd), no SELinux.
  pkg_sync_src
  ./configure --prefix="$prefix" --libdir="${prefix}/lib" --libbpf_force=off
  local -a paths=(
    PREFIX="$prefix"
    LIBDIR="${prefix}/lib"
    SBINDIR="${prefix}/sbin"
    CONF_USR_DIR="${prefix}/share/iproute2"
    CONF_ETC_DIR="${sysconfdir}/iproute2"
    NETNS_RUN_DIR=/run/netns
    NETNS_ETC_DIR="${sysconfdir}/netns"
    ARPDDIR="${localstatedir}/lib/arpd"
    KERNEL_INCLUDE="${prefix}/include"
  )
  pkg_compile "${paths[@]}"
  pkg_install "${paths[@]}"
  grep -q '^HAVE_MNL:=y' config.mk && grep -q '^HAVE_ELF:=y' config.mk && grep -q '^HAVE_CAP:=y' config.mk ||
    { echo "iproute2: libmnl, libelf or libcap not found" >&2; exit 1; }
}
