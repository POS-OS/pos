pkg() {
  # cron.d, anacrontab and the spool directory layout install to /etc and /var
  # and are moved to the factory tree. cronie ships no systemd units; those
  # come with the POS integration files (BUILD.md "System stage").
  pkg_autotools \
    --with-pam \
    --with-inotify \
    --enable-anacron \
    --enable-pie \
    --enable-relro \
    --without-selinux \
    --without-audit
  # The PAM configuration is POS's (pos-integration).
  rm -r "${dest_dir}/etc/pam.d"

  pkg_setuid "${prefix}/bin/crontab"
}
