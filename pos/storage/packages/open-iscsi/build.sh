pkg() {
  # The iSCSI initiator: iscsid, iscsiadm, iscsistart (boot from iSCSI),
  # iscsiuio (offload adapters), libopeniscsiusr, their units, the iBFT
  # generator and udev rule, with iSNS discovery (libisns). Configuration
  # in /etc/iscsi, the node database in /var/lib/iscsi. The initiator name
  # is made per machine by iscsi-init.service on first boot: the one the
  # build generates is removed, or every machine would share it.
  pkg_meson \
    -Disns=enabled \
    -Dsystemddir="${prefix}/lib/systemd" \
    -Drulesdir="${prefix}/lib/udev/rules.d" \
    -Discsi_sbindir="${prefix}/sbin"
  rm "${dest_dir}${sysconfdir}/iscsi/initiatorname.iscsi"
}
