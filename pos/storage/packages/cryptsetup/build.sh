pkg() {
  # Disk encryption: cryptsetup (LUKS1/2, plain, TCRYPT, BitLocker,
  # FileVault2, OPAL), veritysetup, integritysetup and libcryptsetup, which
  # systemd dlopens for crypttab, cryptenroll and homed. OpenSSL as the
  # crypto backend, its Argon2 too (OpenSSL 3.2 and later have it); kernel
  # keyring tokens. No SSH token (libssh) or password quality checks
  # (pwquality). Token plugins in /pos/lib/cryptsetup.
  pkg_meson \
    -Dcrypto-backend=openssl \
    -Dssh-token=false \
    -Dpwquality=false \
    -Dasciidoc=enabled \
    -Dtmpfilesdir="${prefix}/lib/tmpfiles.d"
}
