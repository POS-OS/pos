pkg() {
  # Drive health: smartctl, smartd (sd_notify, its unit) and the drive
  # database in /pos/share/smartmontools, which updates with POS, not with
  # update-smart-drivedb (not installed). smartd.conf, smartd_warning.sh
  # and its plugin directory in /etc. No environment file for the unit, no
  # libcap-ng (smartd keeps its capabilities) or SELinux.
  pkg_autotools \
    --with-libsystemd \
    --with-systemdsystemunitdir="${prefix}/lib/systemd/system" \
    --with-systemdenvfile=no \
    --with-initscriptdir=no \
    --with-update-smart_drivedb=no \
    --with-nvme-devicescan \
    --with-libcap-ng=no \
    --with-selinux=no
}
