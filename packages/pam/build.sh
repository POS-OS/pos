pkg() {
  # No logind support (pam_issue, pam_limits, pam_timestamp): systemd requires
  # pam, so pam cannot link libsystemd. Where systemd is in /pos (an
  # environment that has it for another reason), auto would link it.
  pkg_meson \
        -Dvendordir="${prefix}/share/pam" \
        -Dselinux=disabled \
        -Daudit=disabled \
        -Dlogind=disabled \
        -Delogind=disabled \
        -Ddocs=disabled
}
