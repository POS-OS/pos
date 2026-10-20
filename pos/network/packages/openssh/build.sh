pkg() {
  # Configuration in /etc/ssh, moved to the factory tree with the
  # privilege separation directory, /var/empty/sshd. Host keys are made on
  # the machine, by sshd-keygen.service before sshd starts. sshd notifies
  # systemd itself (Type=notify), without libsystemd. The PATH of a session
  # is login's (pos/system/packages/shadow). No Kerberos, libedit (sftp's
  # line editing), SELinux, audit or FIDO security keys (libfido2).
  pkg_autotools \
    --sysconfdir="${sysconfdir}/ssh" \
    --libexecdir="${prefix}/libexec/openssh" \
    --with-privsep-path="${localstatedir}/empty/sshd" \
    --with-privsep-user=sshd \
    --with-pid-dir=/run \
    --with-pam \
    --with-default-path="/usr/local/bin:/usr/bin:/bin:${prefix}/bin" \
    --with-superuser-path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${prefix}/sbin:${prefix}/bin" \
    --with-mantype=man \
    --without-kerberos5 \
    --without-libedit \
    --without-selinux \
    --disable-security-key \
    --disable-strip

  # The PAM stack goes to pam's vendor directory, as POS's others
  # (pos/system/packages/pos-integration); the units and the privilege
  # separation user are the package's.
  install -D -m 0644 "$recipe_dir/sshd.pam" "${dest_dir}${prefix}/share/pam/pam.d/sshd"
  install -d "${dest_dir}${prefix}/lib/systemd/system"
  install -m 0644 "$recipe_dir"/sshd.service "$recipe_dir"/sshd-keygen.service \
    "${dest_dir}${prefix}/lib/systemd/system/"
  install -D -m 0644 "$recipe_dir/sysusers.conf" "${dest_dir}${prefix}/lib/sysusers.d/openssh.conf"
}
