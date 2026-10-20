# The default PAM configuration goes to pam's vendor directory
# (pos/core-libs/packages/pam: VENDORDIR=/pos/share/pam), not to /etc: it applies
# without being copied, and /etc/pam.d overrides it per service. os-release
# is the system's identity: /usr/lib/os-release links to it (image layout,
# pos-fedora). The presets are POS's, ahead of systemd's. The udev rules
# start services for devices (the QEMU guest agent for its port).
# pos-stage enables the optional stages, which systemd-sysext merges over
# /pos (its drop-in).

pkg() {
  install -d "$dest_dir$prefix/share/pam/pam.d"
  install -m 0644 "$src_dir"/pam.d/* "$dest_dir$prefix/share/pam/pam.d/"
  install -D -m 0644 "$src_dir/os-release" "$dest_dir$prefix/lib/os-release"
  install -d "$dest_dir$prefix/lib/systemd/system-preset"
  install -m 0644 "$src_dir"/presets/*.preset "$dest_dir$prefix/lib/systemd/system-preset/"
  install -d "$dest_dir$prefix/lib/udev/rules.d"
  install -m 0644 "$src_dir"/udev/*.rules "$dest_dir$prefix/lib/udev/rules.d/"
  install -D -m 0755 "$src_dir/bin/pos-stage" "$dest_dir$prefix/sbin/pos-stage"
  install -D -m 0644 "$src_dir/systemd/systemd-sysext.service.d/pos.conf" \
    "$dest_dir$prefix/lib/systemd/system/systemd-sysext.service.d/pos.conf"
}
