pkg() {
  # No set-uid or file capabilities: ping uses ICMP datagram sockets, which
  # systemd's sysctl defaults (net.ipv4.ping_group_range) open to every
  # group. arping and clockdiff need CAP_NET_RAW: run them as root. No IDN
  # (libidn2).
  pkg_meson \
        -DUSE_CAP=true \
        -DUSE_IDN=false \
        -DUSE_GETTEXT=true \
        -DNO_SETCAP_OR_SUID=true \
        -DBUILD_ARPING=true \
        -DBUILD_CLOCKDIFF=true \
        -DBUILD_PING=true \
        -DBUILD_TRACEPATH=true \
        -DBUILD_MANS=true \
        -DBUILD_HTML_MANS=false \
        -DINSTALL_SYSTEMD_UNITS=false \
        -DSKIP_TESTS=true
}
