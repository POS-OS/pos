pkg() {
  # toolbox is one program for both sides: on the host it creates and
  # enters containers, and in a container, bind-mounted as
  # /usr/bin/toolbox, it is the entry point (toolbox init-container). Its
  # build makes it run in either: its loader and its runpath are under
  # /run/host, where a toolbox container has the host's root, and its
  # tmpfiles.d file links /run/host to / on the host. With POS's loader
  # that is /run/host/pos/lib/ld-linux-x86-64.so.2 and the runpath
  # /run/host/pos/lib (the libc.so directory the compiler names); the
  # container's own libraries are never used. src/meson.build names the
  # loader by the root path, /lib64/ld-linux-x86-64.so.2, which the build
  # would resolve on the build container's root: the copy names POS's.
  # POS's LDFLAGS name the loader too; cgo gets them without it, so the
  # one toolbox's build sets is the program's.
  #
  # The completions are made by running toolbox (go run . completion).
  # In the build container, which has /run/.containerenv, toolbox takes
  # itself for a container's entry point, which refuses to start without
  # TOOLBOX_PATH, the path of the host's toolbox it is given there: the
  # build sets it to the program it makes.
  #
  # The profile.d file goes to /etc/profile.d (factory), which
  # pos-integration's /etc/profile reads. The test suite, which meson
  # installs, is left out.
  pkg_sync_src
  sed -i "s|dynamic_linker = '/lib64/ld-linux-x86-64.so.2'|dynamic_linker = '${prefix}/lib/ld-linux-x86-64.so.2'|" \
    "$build_dir/src/meson.build"
  grep -q "dynamic_linker = '${prefix}/lib/ld-linux-x86-64.so.2'" "$build_dir/src/meson.build" ||
    { echo "toolbox: src/meson.build names no x86-64 loader to replace" >&2; exit 1; }
  pkg_go_env
  CGO_LDFLAGS=${LDFLAGS/-Wl,--dynamic-linker=${prefix}\/lib\/ld-linux-x86-64.so.2/}
  meson setup "$build_dir/build" "$build_dir" \
        --prefix="$prefix" \
        --libdir=lib \
        --sysconfdir="$sysconfdir" \
        --localstatedir="$localstatedir" \
        --buildtype=plain \
        -Dbash_completions=enabled \
        -Dbash_completions_dir="${prefix}/share/bash-completion/completions" \
        -Dfish_completions=enabled \
        -Dfish_completions_dir="${prefix}/share/fish/vendor_completions.d" \
        -Dprofile_dir="${sysconfdir}/profile.d" \
        -Dtmpfiles_dir="${prefix}/lib/tmpfiles.d"
  TOOLBOX_PATH="$build_dir/build/src/toolbox" meson compile -C "$build_dir/build" -j "$nproc"
  DESTDIR="$dest_dir" meson install -C "$build_dir/build"
  rm -rf "${dest_dir:?}${prefix}/share/toolbox/test"
}
