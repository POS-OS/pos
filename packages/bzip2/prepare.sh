# Build system fixes.

prep() {
  if [[ -f meson.build ]]; then
    # tests/meson.build requires pytest at configure time, even if tests are
    # not run.
    sed -i "/subdir('tests')/d" meson.build
  elif [[ -f Makefile-libbz2_so ]]; then
    sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
    sed -i 's@(PREFIX)/man@(PREFIX)/share/man@g' Makefile
  fi
}
