pkg() {
  # iptables, ip6tables, arptables and ebtables over nftables
  # (xtables-nft-multi), for tools that write iptables rules: their rules
  # are nftables tables, which nft lists. iptables builds the legacy
  # backend (xtables-legacy-multi, the kernel's x_tables interface) in any
  # case; it is removed here, and the plain names, which iptables links to
  # it, link to the nft one. iptables-xml, its man page and iptables.xslt
  # are legacy's only. No libnetfilter_conntrack (connlabel), libnfnetlink
  # or libpcap (nfbpf_compile, nfsynproxy). The extensions are in
  # /pos/lib/xtables.
  local sbin=${dest_dir}${prefix}/sbin share=${dest_dir}${prefix}/share n
  pkg_autotools \
    --disable-static \
    --enable-nftables \
    --disable-libnfnetlink \
    --disable-connlabel
  rm "$sbin/xtables-legacy-multi" "$sbin"/*-legacy* "${dest_dir}${prefix}/bin/iptables-xml"
  rm "$share/man/man8/xtables-legacy.8" "$share/man/man1/iptables-xml.1" "$share/iptables/iptables.xslt"
  for n in iptables iptables-restore iptables-save ip6tables ip6tables-restore ip6tables-save; do
    ln -sf xtables-nft-multi "$sbin/$n"
  done
}
