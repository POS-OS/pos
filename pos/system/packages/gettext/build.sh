pkg() {
  pkg_sync_src

  # Only the runtime is part of the base image: gettext, ngettext and envsubst
  # for shell scripts. libintl itself comes from glibc. The translation tools
  # (msgfmt, xgettext, autopoint) are build-time and belong to the sdk stage.
  cd "${build_dir}/gettext-runtime" || exit 1
  pkg_autotools \
    --disable-static \
    --disable-java \
    --disable-csharp \
    --disable-libasprintf
}
