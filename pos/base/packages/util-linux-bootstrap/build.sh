# util-linux without libsystemd: systemd links libmount and libblkid,
# and util-linux links libsystemd. No man pages: util-linux, which
# obsoletes it, has them.
configure_extra=(--without-systemd --disable-asciidoc)
# shellcheck source=../util-linux/build.sh
source "$recipe_dir/../util-linux/build.sh"
