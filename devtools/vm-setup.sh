#!/usr/bin/env bash
# Sets up a test system, run in it as root by devtools/vm.sh for
# devtools/vm-libvirt-disk.sh, which puts the settings in front of it:
#
#   TIMEZONE     the time zone, a name of /pos/share/zoneinfo
#   LOCALE       the system's locale (LANG), one of glibc's; empty: none
#   KEYMAP       the console's keyboard layout, a keymap of kbd; empty: none
#   ROOT_HASH    root's password, hashed (crypt(3), as openssl passwd -6)
#   USER_NAME    the user to add, with a home directory; empty: none
#   USER_HASH    the user's password, hashed
#
# The apps to install are the archives (*-app-*.tar.zst) of the directory
# vm.sh shares as pos-share. The container stage is enabled, with the
# stages it requires. Prints what it does; fails at the first step that
# fails.

set -euo pipefail
PATH=/pos/sbin:/pos/bin:/usr/sbin:/usr/bin

# systemd's time zones are /usr/share/zoneinfo's; disks of releases
# before 1.0-11 lack the link to /pos/share/zoneinfo that vm-disk's layout
# makes now.
[[ -e /usr/share/zoneinfo ]] || ln -s ../../pos/share/zoneinfo /usr/share/zoneinfo

# First boot's settings, which a later boot would otherwise ask for.
systemd-firstboot --force --timezone="$TIMEZONE" --root-password-hashed="$ROOT_HASH"
echo "time zone $(readlink /etc/localtime), root password set"

# The locale (/etc/locale.conf), which systemd otherwise leaves at C.UTF-8.
if [[ -n $LOCALE ]]; then
  systemd-firstboot --force --locale="$LOCALE"
  echo "locale $LOCALE"
fi

# The console's keyboard layout (/etc/vconsole.conf), applied now and at
# every boot, in the initramfs too. Disks of releases before 1.0-11 have no
# kbd, and keep the kernel's US layout.
if [[ -n $KEYMAP && -x /pos/bin/loadkeys ]]; then
  systemd-firstboot --force --keymap="$KEYMAP"
  systemctl restart systemd-vconsole-setup.service
  echo "keymap $KEYMAP"
elif [[ -n $KEYMAP ]]; then
  echo "keymap $KEYMAP not set: the disk has no kbd"
fi

# The container stage and those it requires, merged now and at every boot.
pos-stage enable container

# The apps of the shared directory.
share=/run/pos-share
mkdir -p "$share"
mount -t 9p -o trans=virtio,ro pos-share "$share"
for archive in "$share"/*-app-*.tar.zst; do
  [[ -f $archive ]] || continue
  pos-app install "$archive"
done
umount "$share"

# The user, in group wheel when the system has it.
if [[ -n $USER_NAME ]]; then
  groups=()
  ! getent group wheel >/dev/null || groups=(-G wheel)
  useradd -m "${groups[@]}" -p "$USER_HASH" "$USER_NAME"
  echo "user $USER_NAME added"
fi
