# util-linux without libsystemd: systemd links libmount and libblkid,
# and util-linux links libsystemd.
configure_extra=(--without-systemd)
# shellcheck source=../util-linux/build.sh
source "$recipe_dir/../util-linux/build.sh"
