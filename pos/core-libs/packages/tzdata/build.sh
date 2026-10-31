pkg() {
  pkg_sync_src

  # Compile zic and zdump using the POS compiler and flags.
  pkg_compile CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

  # Install zoneinfo data into /pos/share/zoneinfo, and the utilities, which
  # are glibc's (below).
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

  # zic, zdump and tzselect are glibc's, as in Fedora; tzdata is the data
  # (BUILD.md "Overlapping binaries").
  rm -f "${dest_dir}${prefix}/sbin/zic" "${dest_dir}${prefix}/bin/zdump" "${dest_dir}${prefix}/bin/tzselect"
}
