pkg() {
  icu_src=${src_dir}/icu4c/source
  if [[ ! -x $icu_src/configure ]]; then
    echo "missing icu4c/source/configure in $src_dir" >&2
    exit 1
  fi

  pkg_autotools "$icu_src/configure"
}
