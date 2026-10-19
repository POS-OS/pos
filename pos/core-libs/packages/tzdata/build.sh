pkg() {
  pkg_sync_src

  # Compile zic and zdump using the POS compiler and flags.
  pkg_compile CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

  # Install zoneinfo data into /pos/share/zoneinfo and utilities into /pos/{bin,sbin}.
  pkg_install \
    TOPDIR= \
    USRDIR="${prefix#/}" \
    USRSHAREDIR="${prefix#/}/share" \
    BINDIR="${prefix}/bin" \
    ZICDIR="${prefix}/sbin" \
    ZDUMPDIR="${prefix}/bin" \
    TZDIR="${prefix}/share/zoneinfo" \
    MANDIR="${prefix}/share/man" \
    LIBDIR="${prefix}/lib"

  # Do not ship /etc/localtime in the base package; local time is configured per
  # machine via timedatectl or system configuration.
  rm -f "${dest_dir}/etc/localtime"
}
