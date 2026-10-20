pkg() {
  # The library only, for curl's HTTP/2: not the applications (nghttpx,
  # h2load), which need libev, c-ares and C++. The source is synced without
  # its submodules (the applications' third-party code). No documentation
  # (Sphinx).
  pkg_cmake \
        -DENABLE_LIB_ONLY=ON \
        -DENABLE_DOC=OFF \
        -DENABLE_FAILMALLOC=OFF \
        -DBUILD_STATIC_LIBS=OFF \
        -DBUILD_TESTING=OFF
}
