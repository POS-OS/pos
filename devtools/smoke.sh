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
# The modules are out of /usr: /usr/lib/modules links to pos-kernel's
# directory, where vm-disk's kernel is a link into the archive and
# vm-disk-dnf's the kernel package's files.
check "kernel modules in /var/lib/pos/kernel" bash -c '
  [[ $(readlink -f /usr/lib/modules/$(uname -r)) == /var/lib/pos/kernel/* ]] || { ls -l /usr/lib/modules; false; }'
if [[ ! -x /usr/bin/dnf ]]; then
  check "pos-kernel boots the fedora channel" bash -c 'pos-kernel list | grep -x "fedora $(uname -r) default running" ||
    { pos-kernel list; false; }'
fi
check "curl (base stage)" curl --version
check "network link routable" bash -c 'networkctl list --no-legend | grep -q routable || { networkctl list; false; }'
# The root's and the ESP's file systems: ext4 and FAT made and checked in
# image files (e2fsprogs, dosfstools; systemd-fsck runs their fsck).
check "ext4 and FAT tools" bash -c 'truncate -s 64M /var/tmp/smoke-fs.img &&
  mkfs.ext4 -q -F /var/tmp/smoke-fs.img && e2fsck -fn /var/tmp/smoke-fs.img &&
  mkfs.fat /var/tmp/smoke-fs.img && fsck.fat -n /var/tmp/smoke-fs.img; rc=$?; rm -f /var/tmp/smoke-fs.img; exit $rc'
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
# A native system (vm-disk) has the library of stage images: the network
# stage merges over /pos, and its programs run.
if [[ -f /pos/lib/pos/stages/pos-network.raw ]]; then
  check "pos-stage enable network" bash -c 'pos-stage enable network &&
    pos-stage list | grep -qx "network enabled" || { systemd-sysext status; false; }'
  check "network stage tools" bash -c 'ip -br link && ping -c 1 127.0.0.1 &&
    ssh -V && nft --version'
  # iptables writes its rules as an nftables table, which nft lists.
  check "iptables over nftables" bash -c 'iptables -N SMOKE && nft list table ip filter | grep -q SMOKE &&
    iptables -X SMOKE && iptables -V | grep -q nf_tables'
fi
# The storage stage: on a loop device, an LVM volume group with a LUKS2
# volume holding XFS, and a Btrfs volume.
if [[ -f /pos/lib/pos/stages/pos-storage.raw ]]; then
  check "pos-stage enable storage" bash -c 'pos-stage enable storage &&
    pos-stage list | grep -qx "storage enabled" || { systemd-sysext status; false; }'
  # mkfs.exfat -V exits 1 after printing its version.
  check "storage stage tools" bash -c 'mdadm --version && iscsiadm --version && nvme version &&
    smartctl --version >/dev/null && { mkfs.exfat -V || (($? == 1)); } && thin_check -V'
  check "LVM, LUKS, XFS and Btrfs" bash -c 'set -e
    truncate -s 1G /var/tmp/smoke-lvm.img
    dev=$(losetup --show -f /var/tmp/smoke-lvm.img)
    vgcreate -q smoke "$dev" && lvcreate -q -y -L 400M -n crypt smoke && lvcreate -q -y -L 400M -n btrfs smoke
    echo -n smoke-test >/run/smoke.key
    cryptsetup luksFormat -q --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file /run/smoke.key /dev/smoke/crypt
    cryptsetup open --key-file /run/smoke.key /dev/smoke/crypt smoke-luks
    mkfs.xfs -q /dev/mapper/smoke-luks && mkfs.btrfs -q /dev/smoke/btrfs
    mkdir -p /mnt/xfs /mnt/btrfs && mount /dev/mapper/smoke-luks /mnt/xfs && mount /dev/smoke/btrfs /mnt/btrfs
    echo smoke >/mnt/xfs/f && echo smoke >/mnt/btrfs/f && btrfs filesystem df /mnt/btrfs >/dev/null
    umount /mnt/xfs /mnt/btrfs && xfs_repair -n /dev/mapper/smoke-luks && btrfs check /dev/smoke/btrfs
    cryptsetup close smoke-luks && vgremove -q -f smoke && losetup -d "$dev" && rm /var/tmp/smoke-lvm.img'
fi
# The container stage enables the network stage it requires; podman runs
# a container from Docker Hub on its default network and on a network of
# its own (netavark's nftables rules), where aardvark-dns resolves the
# container's name.
if [[ -f /pos/lib/pos/stages/pos-container.raw ]]; then
  check "pos-stage enable container" bash -c 'pos-stage enable container &&
    pos-stage list | grep -q "^container enabled" || { systemd-sysext status; false; }'
  check "podman run" podman run --rm docker.io/library/alpine true
  # getent, not busybox nslookup: the container's resolv.conf has
  # resolved's "search .", and nslookup sends a malformed query for it
  # (write: Message too large) where getent, musl's resolver, skips it.
  check "podman network" bash -c 'podman network create smoke &&
    podman run --rm --network smoke --name smoke-dns docker.io/library/alpine getent hosts smoke-dns'
  # The image tools share podman's storage: buildah commits an image podman
  # runs; skopeo reads a registry's manifest. docker is podman, and
  # podman-remote talks to podman's service.
  check "buildah and skopeo" bash -c 'ctr=$(buildah from docker.io/library/alpine) &&
    buildah run "$ctr" -- touch /smoke && buildah commit -q "$ctr" localhost/smoke >/dev/null &&
    podman run --rm localhost/smoke test -e /smoke &&
    skopeo inspect --format "{{.Digest}}" docker://docker.io/library/alpine'
  check "docker and podman-remote" bash -c 'docker --version | grep -q podman &&
    systemctl start podman.socket && podman-remote info >/dev/null'
  check "toolbox" toolbox --version
fi

exit "$failed"
