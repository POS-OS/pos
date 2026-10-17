pkg() {
  # journald rotates its own journal; logrotate is for everything else.
  # Compression tools are the POS gzip. No logrotate.conf or units are
  # installed by upstream; those come with the POS integration files.
  pkg_autotools \
    --with-state-file-path="${localstatedir}/lib/logrotate/logrotate.status" \
    --with-compress-command="${prefix}/bin/gzip" \
    --with-uncompress-command="${prefix}/bin/gunzip" \
    --with-acl \
    --without-selinux
}
