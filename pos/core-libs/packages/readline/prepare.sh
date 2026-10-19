# Shared libraries are linked without an rpath.

prep() {
  if [[ -f support/shobj-conf ]]; then
    sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
  fi
}
