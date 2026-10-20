#!/usr/bin/env bash
# Stage images for outputs (buildsys/outputs.sh): an optional stage as a
# system extension image, which systemd-sysext merges over /pos on a
# system that enables it (pos-stage). BUILD.md "Stage images".

# Make a stage's archive an extension image, pos-<stage>-<stem>.raw: an
# EROFS file system (lz4hc) of the stage's /pos, and its extension-release,
# which ties it to the build's own base stage: the ID and SYSEXT_LEVEL of
# the base's os-release (assemble.sh). systemd-sysext merges an image
# only onto an os-release with both the same. The extension's name is
# pos-<stage>, the image's name in the library (fs_stage_images).
# Inputs:
#   $1    the stage
#   $2    the stage with /pos/lib/os-release (system)
#   bdir, stem, work, output
sysext_stage() {
  local stage=$1 tree=$work/sysext-$1 img osrel id level
  img=$bdir/pos-$stage-$stem.raw
  osrel=$(tar --zstd -xOf "$bdir/pos-$2-$stem.tar.zst" pos/lib/os-release) ||
    die "$output: stage $2 has no pos/lib/os-release"
  id=$(sed -n 's/^ID=//p' <<<"$osrel")
  level=$(sed -n 's/^SYSEXT_LEVEL=//p' <<<"$osrel")
  [[ -n $id && -n $level ]] || die "$output: the os-release of stage $2 has no ID or SYSEXT_LEVEL"
  rm -rf "$tree"
  mkdir -p "$tree/usr/lib/extension-release.d"
  tar --zstd -xpf "$bdir/pos-$stage-$stem.tar.zst" -C "$tree"
  find "$tree" ! -type l -perm -g=w ! -perm -1000 -exec chmod g-w {} +
  printf 'ID=%s\nSYSEXT_LEVEL=%s\nARCHITECTURE=x86-64\n' "$id" "$level" \
    >"$tree/usr/lib/extension-release.d/extension-release.pos-$stage"
  rm -f "$img.tmp"
  mkfs.erofs --quiet -zlz4hc --all-root "$img.tmp" "$tree"
  mv "$img.tmp" "$img"
  rm -rf "$tree"
  echo "$img"
}
