pkg() {
  # kmod searches /usr/lib/{modprobe,depmod}.d by default; distconfdir points
  # that at the prefix. Modules stay in /usr/lib/modules: POS boots kernels
  # other projects build, and their packages install modules there (as
  # systemd's kernel-install expects).
  pkg_meson \
        -Ddistconfdir="${prefix}/lib" \
        -Dmoduledir=/usr/lib/modules \
        -Dopenssl=enabled \
        -Dmbedtls=disabled \
        -Dzlib=enabled \
        -Dxz=enabled \
        -Dzstd=enabled \
        -Dmanpages=false \
        -Ddocs=false \
        -Dbuild-tests=false
  # The kernel loads modules on demand (a file system's, mounting the ESP) by
  # running the modprobe its build names, /sbin/modprobe or /usr/bin/modprobe;
  # the kernels POS boots are built by others, so the path is set at boot.
  install -d "${dest_dir}${prefix}/lib/sysctl.d"
  printf 'kernel.modprobe = %s\n' "${prefix}/sbin/modprobe" \
    >"${dest_dir}${prefix}/lib/sysctl.d/50-kmod.conf"
}
