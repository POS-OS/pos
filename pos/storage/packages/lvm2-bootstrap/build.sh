# lvm2's device-mapper part (libdevmapper, dmsetup) without udev
# synchronization or libsystemd: systemd builds against cryptsetup, which
# links libdevmapper, and lvm2 links libudev and libsystemd. lvm2 replaces
# it once built (BUILD.md "Circular dependencies").
configure_extra=(
  --disable-udev_sync
  --disable-udev_rules
  --disable-systemd-journal
  --disable-app-machineid
  --disable-sd-notify
  --disable-blkid_wiping
  --disable-readline
  --disable-dmeventd
  --disable-lvmpolld
)
lvm2_make=(device-mapper)
lvm2_install=(install_device-mapper)
# shellcheck source=../lvm2/build.sh
source "$recipe_dir/../lvm2/build.sh"
