pkg() {
  # GNU Wget2 and libwget, with OpenSSL (its default is GnuTLS, which POS
  # does not have) and OpenSSL's trust store, HTTP/2 with nghttp2, and
  # zlib, zstd, xz and bzip2 content encoding. Left out, as POS lacks the
  # libraries: libpsl, libhsts, IDN (libidn2), DANE, GPGME, brotli, lzip,
  # libproxy. No documentation: the man page needs pandoc. wget links to
  # wget2, as Fedora's wget2-wget has it. LDCONFIG=: keeps make install
  # from running ldconfig; wget2_noinstall, a copy of wget2 for the test
  # suite, is removed, as Fedora does.
  pkg_autotools \
    --disable-static \
    --disable-doc \
    --with-ssl=openssl \
    --with-libnghttp2 \
    --with-zlib \
    --with-zstd \
    --with-lzma \
    --with-bzip2 \
    --with-libpcre2 \
    --without-libpcre \
    --enable-xattr \
    --without-libpsl \
    --without-libhsts \
    --without-libidn2 \
    --without-libidn \
    --without-libdane \
    --without-gpgme \
    --without-brotlidec \
    --without-lzip \
    --without-libmicrohttpd \
    LDCONFIG=:
  rm "${dest_dir}${prefix}/bin/wget2_noinstall"
  ln -s wget2 "${dest_dir}${prefix}/bin/wget"
}
