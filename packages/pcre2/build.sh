pkg() {
  pkg_autotools \
    --disable-static \
    --enable-unicode-properties \
    --enable-pcre2-16 \
    --enable-pcre2-32
}
