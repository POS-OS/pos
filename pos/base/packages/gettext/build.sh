pkg() {
  pkg_sync_src

  # Only the runtime is part of the base image: gettext, ngettext and envsubst
  # for shell scripts. libintl itself comes from glibc. The translation tools
  # (msgfmt, xgettext, autopoint) are build-time, not part of pos.
  cd "${build_dir}/gettext-runtime" || exit 1
  pkg_configure \
    --disable-static \
    --disable-java \
    --disable-csharp \
    --disable-libasprintf
  # The man pages come from --help through help2man. The copy in man/ needs
  # Locale::gettext; the build tools' help2man does not in the C locale.
  # x-to-1 runs it as "$PERL $HELP2MAN", so it takes the script's path.
  local help2man
  help2man=$(command -v help2man) || exit 1
  pkg_compile HELP2MAN="$help2man"
  pkg_install HELP2MAN="$help2man"
}
