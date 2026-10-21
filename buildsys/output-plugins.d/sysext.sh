#!/usr/bin/env bash
# Stage images for outputs (buildsys/outputs.sh): an optional stage as a
# system extension image, which systemd-sysext merges over /pos on a
# system that enables it (pos-stage). BUILD.md "Stage images".

# The stage whose member list (pos/<tree>/stage) names a package.
# Inputs:
#   $1    package name
#   base
# Outputs:
#   the stage name on stdout; nothing when no stage lists it
sysext_stage_of() {
  local f
  for f in "$base"/pos/*/stage; do
    if sed -e 's/#.*//' "$f" | grep -qxF -- "$1"; then
      basename "$(dirname "$f")"
      return 0
    fi
  done
}

# Make a stage's archive an extension image, pos-<stage>-<stem>.raw: an
# EROFS file system (lz4hc) of the stage's /pos, and its extension-release,
# which ties it to the build's base: the ID and SYSEXT_LEVEL of the
# base's os-release (assemble.sh). systemd-sysext merges an image only
# onto an os-release with both the same. The extension's name is
# pos-<stage>, the image's name in the library (fs_stage_images).
#
# The stages it needs besides the base are written next to it, one per
# line, as pos-<stage>-<stem>.requires: the stages of the run-time
# requirements of its packages (their installed meta), which pos-stage
# enables with it.
# Inputs:
#   $1      the stage
#   ${@:2}  the base stages, one of them with /pos/lib/os-release
#   bdir, stem, work, output, base
sysext_stage() {
  local stage=$1 tree=$work/sysext-$1 img osrel='' id level s req of
  local -A skip=([$1]=1) needs=()
  shift
  img=$bdir/pos-$stage-$stem.raw
  for s in "$@"; do
    skip[$s]=1
    osrel=$(tar --zstd -xOf "$bdir/pos-$s-$stem.tar.zst" pos/lib/os-release 2>/dev/null) && break
  done
  [[ -n $osrel ]] || die "$output: no pos/lib/os-release in the base stages: $*"
  id=$(sed -n 's/^ID=//p' <<<"$osrel")
  level=$(sed -n 's/^SYSEXT_LEVEL=//p' <<<"$osrel")
  [[ -n $id && -n $level ]] || die "$output: the base's os-release has no ID or SYSEXT_LEVEL"
  rm -rf "$tree"
  mkdir -p "$tree/usr/lib/extension-release.d"
  tar --zstd -xpf "$bdir/pos-$stage-$stem.tar.zst" -C "$tree"
  find "$tree" ! -type l -perm -g=w ! -perm -1000 -exec chmod g-w {} +
  printf 'ID=%s\nSYSEXT_LEVEL=%s\nARCHITECTURE=x86-64\n' "$id" "$level" \
    >"$tree/usr/lib/extension-release.d/extension-release.pos-$stage"

  while read -r req; do
    of=$(sysext_stage_of "$req")
    if [[ -z $of ]]; then
      echo "warning: $output: $stage requires $req, which no stage lists" >&2
    elif [[ -z ${skip[$of]:-} ]]; then
      needs[$of]=1
    fi
  done < <(awk '$1 == "requires" {for (i = 2; i <= NF; i++) print $i}' "$tree"/pos/lib/pos/packages/*/meta | sort -u)
  printf '%s\n' "${!needs[@]}" | sed '/^$/d' | sort >"$bdir/pos-$stage-$stem.requires"

  rm -f "$img.tmp"
  mkfs.erofs --quiet -zlz4hc --all-root "$img.tmp" "$tree"
  mv "$img.tmp" "$img"
  rm -rf "$tree"
  echo "$img"
}
