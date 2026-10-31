pkg() {
  # TLS with OpenSSL from core-libs, which also has the trust store: no CA
  # bundle of curl's own, OpenSSL's default (/etc/ssl/cert.pem, see
  # pos/core-libs/packages/ca-certificates) or SSL_CERT_FILE. HTTP/2 with
  # nghttp2; zlib and zstd content encoding. Left out, as POS lacks the
  # libraries: brotli, libidn2 (IDN), libpsl (cookie domains), libssh2
  # (scp:, sftp:), GSSAPI and LDAP. OpenSSL and zlib are looked up in /pos
  # first, so cmake's modules do not find Fedora's.
  pkg_cmake \
        -DOPENSSL_ROOT_DIR="$prefix" \
        -DZLIB_ROOT="$prefix" \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_STATIC_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DCURL_USE_OPENSSL=ON \
        -DCURL_CA_BUNDLE=none \
        -DCURL_CA_PATH=none \
        -DCURL_CA_FALLBACK=ON \
        -DUSE_NGHTTP2=ON \
        -DCURL_ZLIB=ON \
        -DCURL_ZSTD=ON \
        -DCURL_BROTLI=OFF \
        -DUSE_LIBIDN2=OFF \
        -DCURL_USE_LIBPSL=OFF \
        -DCURL_USE_LIBSSH2=OFF \
        -DCURL_USE_LIBSSH=OFF \
        -DCURL_USE_GSSAPI=OFF \
        -DCURL_DISABLE_LDAP=ON \
        -DENABLE_THREADED_RESOLVER=ON \
        -DENABLE_IPV6=ON
}
