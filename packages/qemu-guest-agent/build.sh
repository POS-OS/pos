pkg() {
  # Only the guest agent: no emulators, tools, docs, plugins or firmware.
  # --disable-download: everything comes from the prepared tree (keycodemapdb,
  # packages/qemu/prepare.sh) and the build host (configure's Python
  # packages, host-requires). qemu looks for libudev only when it builds
  # emulators or tools, so the agent has no udev details of disks (device
  # nodes, serial numbers in guest-get-disks and guest-get-fsinfo).
  pkg_configure "$src_dir/configure" \
    --disable-download \
    --disable-system \
    --disable-user \
    --disable-tools \
    --disable-docs \
    --disable-plugins \
    --disable-install-blobs \
    --disable-selinux \
    --enable-guest-agent
  ninja -j "$nproc" qga/qemu-ga
  # meson install would add keymaps, device trees and trace events, which
  # only the emulators use: the agent and its unit are installed by hand.
  install -D -m 0755 qga/qemu-ga "${dest_dir}${prefix}/bin/qemu-ga"
  unit=${dest_dir}${prefix}/lib/systemd/system/qemu-guest-agent.service
  install -D -m 0644 "$src_dir/contrib/systemd/qemu-guest-agent.service" "$unit"
  sed -i "s|/usr/bin/qemu-ga|${prefix}/bin/qemu-ga|" "$unit"
  ! grep -q '/usr/' "$unit" || { echo "qemu-guest-agent: $unit still names /usr" >&2; exit 1; }
}
