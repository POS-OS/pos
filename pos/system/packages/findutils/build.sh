pkg() {
  # localstatedir is where updatedb writes locatedb.
  pkg_autotools \
    --localstatedir="${localstatedir}/lib/locate" \
    --without-selinux
}
