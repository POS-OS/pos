# The build installs the man pages committed in the tree, which upstream
# regenerates only for a release (scripts/release.sh: update-docs); on
# master, newer commands have none yet (nvme-top). They are generated
# here, as for a release: asciidoc and xmlto for nvme-cli's pages, the
# kernel-doc script and Sphinx for libnvme's. The configuration is only
# for the documentation, so it needs none of the libraries, and installs
# none: -Ddocs=false still generates them, and would not look for the
# committed pages.

prep() {
  meson setup .docs-build \
    --wrap-mode=nodownload \
    -Ddocs=false \
    -Dpython=disabled \
    -Dtests=false \
    -Dexamples=false \
    -Djson-c=disabled \
    -Dopenssl=disabled \
    -Dkeyutils=disabled \
    -Dlibkmod=disabled \
    -Dliburing=disabled \
    -Dlibarchive=disabled \
    -Dmdns=disabled \
    -Dkmip=disabled
  meson compile -C .docs-build update-docs
  rm -rf .docs-build
  [[ -f Documentation/nvme-top.1 ]] || {
    echo "nvme-cli: man pages not generated" >&2
    exit 1
  }
}
