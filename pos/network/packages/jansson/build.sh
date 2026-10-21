pkg() {
  # The JSON library of nft's JSON mode (nft -j), which netavark drives
  # (pos/container/packages/netavark). Shared, soname libjansson.so.4 as
  # Fedora's. No documentation (Sphinx), examples or tests.
  pkg_cmake \
        -DJANSSON_BUILD_SHARED_LIBS=ON \
        -DJANSSON_BUILD_DOCS=OFF \
        -DJANSSON_EXAMPLES=OFF \
        -DJANSSON_WITHOUT_TESTS=ON
}
