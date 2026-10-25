pkg() {
  # LVM and device-mapper: the lvm tools, dmsetup, dmeventd, lvmpolld,
  # libdevmapper and liblvm2cmd, with udev synchronization (their udev
  # rules), the journal, sd_notify, app-specific machine IDs and blkid
  # signature wiping. No NVMe WWIDs: lvm2 reads them with libnvme 1, and
  # nvme-cli's tree now has libnvme 3 (libnvme3.pc), a new API. configure is
  # committed. Run-time directories in /run, as Fedora; the device nodes
  # root:disk 0660; the devices file on by default. Thin, cache, writecache
  # and integrity volumes built in, checked with thin-provisioning-tools'
  # programs; no VDO (its vdoformat is not packaged) and no D-Bus service
  # (Python). /etc/lvm is created by lvm as needed, /run/lvm by its
  # tmpfiles.d file.
  #
  # lvm2-bootstrap builds the device-mapper part only (lvm2_make,
  # lvm2_install) with the libraries that need systemd left out.
  pkg_configure \
    --with-default-dm-run-dir=/run \
    --with-default-run-dir=/run/lvm \
    --with-default-pid-dir=/run \
    --with-default-locking-dir=/run/lock/lvm \
    --with-device-uid=0 \
    --with-device-gid=6 \
    --with-device-mode=0660 \
    --with-default-use-devices-file=1 \
    --with-systemd-run="${prefix}/bin/systemd-run" \
    --with-thin=internal \
    --with-thin-check="${prefix}/sbin/thin_check" \
    --with-thin-dump="${prefix}/sbin/thin_dump" \
    --with-thin-repair="${prefix}/sbin/thin_repair" \
    --with-thin-restore="${prefix}/sbin/thin_restore" \
    --with-cache=internal \
    --with-cache-check="${prefix}/sbin/cache_check" \
    --with-cache-dump="${prefix}/sbin/cache_dump" \
    --with-cache-repair="${prefix}/sbin/cache_repair" \
    --with-cache-restore="${prefix}/sbin/cache_restore" \
    --with-writecache=internal \
    --with-integrity=internal \
    --with-vdo=none \
    --enable-udev_sync \
    --enable-udev_rules \
    --enable-systemd-journal \
    --enable-app-machineid \
    --enable-sd-notify \
    --enable-blkid_wiping \
    --disable-nvme-wwid \
    --enable-readline \
    --enable-cmdlib \
    --enable-dmeventd \
    --enable-lvmpolld \
    --enable-pkgconfig \
    --enable-fsadm \
    --enable-write_install \
    --disable-dbus-service \
    --disable-selinux
  pkg_compile "${lvm2_make[@]:-all}"
  local -a install=(install install_systemd_units install_systemd_generators install_tmpfiles_configuration)
  pkg_install "${lvm2_install[@]:-${install[@]}}"
}
