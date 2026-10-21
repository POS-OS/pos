pkg() {
  # The JSON library of crun and its libocispec. Shared only; no tools
  # (json_parse) or tests.
  pkg_cmake \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_STATIC_LIBS=OFF \
        -DBUILD_APPS=OFF \
        -DBUILD_TESTING=OFF \
        -DDISABLE_WERROR=ON
}
