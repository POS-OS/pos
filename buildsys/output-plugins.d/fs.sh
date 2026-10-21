#!/usr/bin/env bash
# Root filesystem trees for outputs (buildsys/outputs.sh): an image's root
# with POS installed, from the stage archives or with dnf from the build's
# RPM packages, archived for podman import or made into a disk (disk.sh).
# The functions run in output(), as root of a build container, on one tree,
# $work/root. BUILD.md "Images".

# Extract the output's stages (stages) into the tree, in order. Nothing
# in it is group-writable except the sticky directories (/tmp): build
# trees can carry group write from the umask or default ACLs of the build
# directory.
# Inputs:
#   stages, bdir, stem, work
fs_stages() {
  local s a
  mkdir -p "$work/root"
  for s in "${stages[@]}"; do
    a=$bdir/pos-$s-$stem.tar.zst
    [[ -f $a ]] || die "$output: stage $s is not assembled in $bdir"
    tar --zstd -xpf "$a" -C "$work/root"
  done
  find "$work/root" ! -type l -perm -g=w ! -perm -1000 -exec chmod g-w {} +
}

# Put stage images into the tree's library of stage images,
# /pos/lib/pos/stages/pos-<stage>.raw, which pos-stage enables them from
# (BUILD.md "Stage images"), each with pos-<stage>.requires, the other
# stages it needs. The images are what stage-images made.
# Inputs:
#   $@    the stages
#   bdir, stem, work, output
fs_stage_images() {
  local s img lib=$work/root/pos/lib/pos/stages
  mkdir -p "$lib"
  for s in "$@"; do
    img=$bdir/pos-$s-$stem.raw
    [[ -f $img && -f ${img%.raw}.requires ]] ||
      die "$output: stage $s has no image in $bdir (output stage-images)"
    install -m 0644 "$img" "$lib/pos-$s.raw"
    install -m 0644 "${img%.raw}.requires" "$lib/pos-$s.requires"
  done
}

# Make the root layout around /pos: the directories with their modes and
# the symlinks into /pos for the paths in BUILD.md "Prefix".
#   dir <path> <mode>        directory
#   link <path> <target>     symlink
# Inputs:
#   $1    layout file (outputs/<output>/layout)
#   work
fs_layout() {
  local kind path arg
  while read -r kind path arg; do
    case $kind in
      ''|'#'*) ;;
      dir) install -d -m "$arg" "$work/root$path" ;;
      link)
        install -d -m 0755 "$work/root$(dirname "$path")"
        ln -sfn "$arg" "$work/root$path"
        ;;
      *) die "$1: unknown entry: $kind" ;;
    esac
  done <"$1"
}

# Copy files into the tree (configuration, such as /etc/kernel), owned by
# root, with the modes of the umask, not the checkout's.
# Inputs:
#   $1    directory whose contents are copied (outputs/<output>/root)
#   work
fs_copy() {
  mkdir -p "$work/root"
  cp -R --no-preserve=mode,ownership "$1/." "$work/root/"
}

# Put the packages' shipped defaults into /etc and /var: the
# factory-<package>.conf tmpfiles.d files (buildsys/pkg.sh _pkg_factory)
# applied by the tree's own systemd-tmpfiles, as a boot would. It runs
# through the tree's loader, so /pos need not be installed where this
# runs.
# Inputs:
#   work
fs_factory() {
  local root=$work/root f
  local -a confs=()
  for f in "$root"/pos/lib/tmpfiles.d/factory-*.conf; do
    [[ -f $f ]] && confs+=("$f")
  done
  ((${#confs[@]})) || return 0
  SYSTEMD_LOG_LEVEL=warning "$root/pos/lib/ld-linux-x86-64.so.2" \
    --library-path "$root/pos/lib:$root/pos/lib/systemd" \
    "$root/pos/bin/systemd-tmpfiles" --root="$root" --create "${confs[@]}"
}

# Create the users and groups of the packages' sysusers.d, by the tree's
# systemd-sysusers run through its loader. A tree made with dnf has them
# from rpm.
# Inputs:
#   work
fs_sysusers() {
  local root=$work/root
  SYSTEMD_LOG_LEVEL=warning "$root/pos/lib/ld-linux-x86-64.so.2" \
    --library-path "$root/pos/lib:$root/pos/lib/systemd" \
    "$root/pos/bin/systemd-sysusers" --root="$root"
  rm -f "$root/etc/.pwd.lock"
}

# Install RPM packages into the tree with dnf: a name the build made an RPM
# package of (pos, pos-*) from that file in <bdir>/rpm, anything else from
# Fedora's repositories. The scriptlets run in the tree as on a running
# system: kernel-install and depmod need /proc, dracut /sys and /dev. /boot
# is a file system of its own, as the ESP is when the system runs:
# kernel-install's boot loader entries name files relative to the file
# system /boot is on. The mounts are in a mount namespace of their own,
# gone when dnf is done; what was written to /boot is kept in $work/boot
# and moved into the tree after. The installed packages are listed in
# pos-<output>-<stem>.packages.
# Inputs:
#   $@    package names
#   bdir, evr, work
fs_dnf() {
  local root=$work/root name f fedora
  local -a pkgs=()
  fedora=$(rpm -E %fedora)
  for name in "$@"; do
    f=$bdir/rpm/$name-$evr.x86_64.rpm
    if [[ $name == pos || $name == pos-* ]]; then
      [[ -f $f ]] || die "$output: no RPM package $name in $bdir/rpm"
      pkgs+=("$f")
    else
      pkgs+=("$name")
    fi
  done
  mkdir -p "$root" "$work/boot"
  export root fedora
  unshare -m bash -euo pipefail -c '
  boot=$1
  shift
  for d in proc sys dev boot; do
    mkdir -p "$root/$d"
  done
  mount -t proc proc "$root/proc"
  mount --rbind /sys "$root/sys"
  mount --rbind /dev "$root/dev"
  mount -t tmpfs -o mode=0755 tmpfs "$root/boot"
  dnf -y --installroot="$root" --releasever="$fedora" --use-host-config \
    --setopt=install_weak_deps=False install "$@"
  cp -a "$root/boot/." "$boot/"
  ' fs_dnf "$work/boot" "${pkgs[@]}"
  cp -a "$work/boot/." "$root/boot/"
  rm -rf "$work/boot"
  dnf -y -q --installroot="$root" --releasever="$fedora" --use-host-config clean all
  # No package creates /tmp: on Fedora, systemd-tmpfiles and the image
  # builders do. librepo (dnf) needs it.
  install -d -m 1777 "$root/tmp"
  rpm --root "$root" -qa --qf '%{name}-%{evr}.%{arch}\n' | sort >"$(output_file packages)"
}

# Install a hosted kernel into a tree without rpm: the Fedora packages are
# downloaded and unpacked into it, then POS's kernel-install adds the
# kernel, as Fedora's scriptlet does on an RPM system: its plugins run
# depmod, dracut (the initramfs) and write the boot loader entry into
# /boot (configured by /etc/kernel). The packages' /lib/modules is the
# tree's link to /usr/lib/modules, where POS's kmod looks, which tar does
# not write through: they are unpacked next to the tree and merged into
# it. /proc, /sys, /dev and /boot are mounted as for fs_dnf.
# Inputs:
#   $@    Fedora kernel package names
#   work
fs_kernel() {
  local root=$work/root rpms=$work/kernel-rpms f kver
  local -a kvers
  rm -rf "$rpms" "$work/boot"
  mkdir -p "$rpms/tree" "$work/boot"
  dnf -q download --releasever="$(rpm -E %fedora)" --destdir="$rpms" "$@"
  for f in "$rpms"/*.rpm; do
    rpm2archive - <"$f" | tar -xzf - -C "$rpms/tree"
  done
  rsync -a --keep-dirlinks "$rpms/tree/" "$root/"
  rm -rf "$rpms"
  mapfile -t kvers < <(ls "$root/usr/lib/modules")
  ((${#kvers[@]} == 1)) || die "$output: expected one kernel, found: ${kvers[*]}"
  kver=${kvers[0]}
  export root kver
  unshare -m bash -euo pipefail -c '
  mount -t proc proc "$root/proc"
  mount --rbind /sys "$root/sys"
  mount --rbind /dev "$root/dev"
  mount -t tmpfs -o mode=0755 tmpfs "$root/boot"
  chroot "$root" env PATH=/pos/bin:/pos/sbin \
    kernel-install add "$kver" "/usr/lib/modules/$kver/vmlinuz"
  cp -a "$root/boot/." "$1/"
  ' fs_kernel "$work/boot"
  cp -a "$work/boot/." "$root/boot/"
  rm -rf "$work/boot" "$root/var/tmp/"*
}

# Archive the tree as pos-<output>-<stem>.tar.zst. Owners are kept as
# numbers: the users exist in the tree's /etc/passwd.
# Inputs:
#   work
fs_archive() {
  local archive
  archive=$(output_file tar.zst)
  tar --numeric-owner --sort=name -C "$work/root" -cf - . | zstd -q -f -T0 -o "$archive.tmp"
  mv "$archive.tmp" "$archive"
  echo "$archive"
}
