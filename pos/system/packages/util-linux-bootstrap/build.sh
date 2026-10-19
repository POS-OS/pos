# util-linux without libsystemd: systemd links libmount and libblkid,
# and util-linux links libsystemd.
configure_extra=(--without-systemd)
# shellcheck source=packages/util-linux/build.sh
source "$base/packages/util-linux/build.sh"
