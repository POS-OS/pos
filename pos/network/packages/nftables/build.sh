pkg() {
  # The interactive mode (nft -i) uses readline from core-libs, not libedit.
  # No JSON (libjansson) or iptables compatibility (libxtables).
  # nftables.service loads /etc/nftables/rules/main.nft when the machine has
  # one; the sample rule sets are in /pos/share/nftables and main.nft, a
  # start for it, in the package's doc directory. The OS fingerprints
  # install to /etc/nftables/osf and move to the factory tree.
  pkg_autotools \
    --disable-static \
    --with-cli=readline \
    --without-json \
    --without-xtables \
    --with-unitdir="${prefix}/lib/systemd/system"
}
