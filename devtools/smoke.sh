#!/usr/bin/env bash
# Checks of a booted image, run in it as root by devtools/vm.sh:
#
#   devtools/vm.sh -c devtools/smoke.sh [<id>]
#
# One line per check, ok or FAIL with what the check printed (its first
# ten lines); the exit status is the number of failed checks. The dnf check,
# made where dnf is installed, needs the network.

PATH=/pos/sbin:/pos/bin:/usr/sbin:/usr/bin
failed=0

check() {
  local name=$1 out
  shift
  if out=$("$@" 2>&1); then
    echo "ok   $name"
  else
    echo "FAIL $name"
    [[ -z $out ]] || sed -e '11,$d' -e 's/^/     /' <<<"$out"
    (($(wc -l <<<"$out") <= 10)) || echo "     ... $(($(wc -l <<<"$out") - 10)) more lines"
    failed=$((failed + 1))
  fi
}

# Succeeds when the boot's journal has no line matching the pattern.
journal_lacks() {
  ! journalctl -b -o cat --no-pager | grep -E "$1"
}

check "system running" systemctl is-system-running --wait
check "os-release is POS's" grep -x 'ID=pos' /etc/os-release
check "os-release names the build" grep '^BUILD_ID=' /etc/os-release
check "boot entry is POS's" bash -c 'ls /boot/loader/entries | grep "^pos-" || { ls /boot/loader/entries; false; }'
check "no failed units" bash -c 'out=$(systemctl --failed --no-legend --plain); [[ -z $out ]] || { echo "$out"; false; }'
check "initrd loads modules (kmod context)" journal_lacks 'Failed to initialize kmod context'
check "unit files not executable" journal_lacks 'is marked executable'
# The display's console (tty1) as a screen dump: agetty waiting there for a
# login name, not for a login program it cannot find.
check "login prompt on tty1" bash -c 'for i in {1..10}; do
  grep -aq "login: " /dev/vcs1 && exit 0; sleep 1; done; tr -s " " </dev/vcs1; false'
# A login shell's PATH comes from login.defs (ENV_SUPATH, ENV_PATH).
check "login PATH (root)" runuser -l root -c 'command -v systemctl'
check "login PATH (user)" runuser -l nobody -s /pos/bin/sh -c 'command -v ls'
# vm.sh's disk is bigger than the image: the root partition grows into it
# (systemd-repart, /etc/repart.d), its file system with it (systemd-growfs).
check "root fills its disk" bash -c 'part=$(findmnt -no SOURCE /)
  disk=/dev/$(lsblk -no PKNAME "$part")
  free=$(sfdisk -F "$disk" | sed -n "s/^Unpartitioned space .* \([0-9]*\) bytes,.*/\1/p")
  psize=$(blockdev --getsize64 "$part")
  fsize=$(df -B1 --output=size / | tail -n 1)
  echo "$disk: $free bytes unpartitioned; $part: $psize bytes, file system $fsize"
  ((free < 16 << 20 && fsize * 10 > psize * 9))'
# vm.sh gives the VM the guest agent's port: udev starts the agent, which
# keeps running on it (its unit restarts it when it exits).
check "QEMU guest agent" bash -c 'systemctl is-active qemu-guest-agent &&
  [[ $(systemctl show -P NRestarts qemu-guest-agent) == 0 ]] ||
  { systemctl status --no-pager qemu-guest-agent; false; }'
check "modprobe" bash -c 'modprobe vfat && grep -q "^vfat " /proc/modules'
check "network link routable" bash -c 'networkctl list --no-legend | grep -q routable || { networkctl list; false; }'
# On an RPM system (vm-dnf): Fedora packages install on top of POS.
if [[ -x /usr/bin/dnf ]]; then
  check "dnf install" bash -c 'dnf -y -q install tree >/dev/null && tree --version'
fi
check "PAM: chpasswd" bash -c 'echo "root:smoke-test" | chpasswd'
check "PAM: su" su -s /pos/bin/sh -c true nobody
check "PAM: runuser" runuser -u nobody -- true
check "PAM: passwd" passwd -S root
check "sudo" bash -c 'useradd -m smoke && echo "smoke:smoke-test" | chpasswd &&
  echo "smoke ALL=(ALL) ALL" >/etc/sudoers.d/smoke &&
  su -s /pos/bin/bash -c "echo smoke-test | sudo -S -k true" smoke'

exit "$failed"
