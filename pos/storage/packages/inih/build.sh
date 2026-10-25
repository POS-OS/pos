pkg() {
  # The INI parser xfsprogs reads mkfs.xfs configuration files with.
  # Shared, without the C++ INIReader.
  pkg_meson \
    -Ddefault_library=shared \
    -Ddistro_install=true \
    -Dwith_INIReader=false
}
