pkg() {
  # NVMe management: nvme (with its vendor plugins), libnvme (libnvme3, in
  # nvme-cli's tree), NVMe over Fabrics discovery and autoconnect (udev
  # rules, units, dracut configuration), nvme-discoverd, and the committed
  # man pages. TLS keys need keyutils, which POS lacks; no mDNS discovery
  # (Avahi), KMIP, libarchive (log archives) or Python bindings. Missing
  # dependencies fail the build instead of being fetched as subprojects.
  pkg_meson \
    --wrap-mode=nodownload \
    -Ddocs=man \
    -Dpython=disabled \
    -Dtests=false \
    -Dexamples=false \
    -Dkeyutils=disabled \
    -Dmdns=disabled \
    -Dkmip=disabled \
    -Dlibarchive=disabled \
    -Dsystemctl="${prefix}/bin/systemctl"
}
