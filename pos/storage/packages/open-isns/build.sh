pkg() {
  # iSNS (iSCSI target discovery): libisns, which open-iscsi links, and
  # isnsd, isnsdd and isnsadm with isnsd's units. Authentication with
  # OpenSSL; no SLP (OpenSLP).
  pkg_meson \
    -Dsecurity=enabled \
    -Dslp=disabled \
    -Drundir=/run \
    -Dsystemddir="${prefix}/lib/systemd"
}
