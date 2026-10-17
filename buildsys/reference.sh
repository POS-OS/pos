#!/usr/bin/env bash
# Reference build management. Sourced by buildsys/build.sh.
#
# A reference is a stored toolchain build (in work/references/<ref>, restored
# from POS_REFERENCE_DIR / reference-dir). A pos build builds against the
# reference toolchain, and assembles stages using the reference's packages.

# The reference a new build uses: the reference setting, else the one the
# reference store marks the default, else none.
# Inputs:
#   config(reference), config(reference-dir)
reference_choose() {
  local ref store
  ref=$(config reference)
  store=$(config reference-dir)
  if [[ -z $ref && -n $store && -f $store/default ]]; then
    ref=$(<"$store/default")
  fi
  echo "${ref:-none}"
}

# Unpack a reference/SDK from the store into work/references/<ref>, unless it
# is there. The store is a directory; this is where a remote one would be
# fetched from. Supports tar archives (pos-ref-$ref.tar.zst or pos-sdk-$ref.tar.zst)
# or direct directory stores ($store/$ref).
# Inputs:
#   $1      reference ID or "none"
#   refs    work/references directory
reference_restore() {
  local ref=$1 store archive
  [[ $ref != none && ! -f $refs/$ref/info ]] || return 0
  store=$(config reference-dir)
  [[ -n $store ]] || die "reference $ref is not in $refs, and reference-dir (or POS_SDK_DIR) is not set"
  if [[ -f $store/$ref/info ]]; then
    rm -rf "$refs/$ref"
    ln -sfn "$store/$ref" "$refs/$ref"
    return 0
  fi
  archive=$store/pos-ref-$ref.tar.zst
  [[ -f $archive ]] || archive=$store/pos-sdk-$ref.tar.zst
  [[ -f $archive ]] || die "no reference $ref: missing pos-ref-$ref.tar.zst (or pos-sdk-$ref.tar.zst) in $store"
  echo "restoring reference $ref from $archive" >&2
  rm -rf "$refs/$ref.tmp"
  mkdir -p "$refs/$ref.tmp"
  tar --zstd -xf "$archive" -C "$refs/$ref.tmp"
  mv "$refs/$ref.tmp" "$refs/$ref"
}

# The packages of a reference the resolver may use, with the requirements
# they were built with (resolve.sh: REF, REF_REQ). A reference is a
# toolchain or external SDK build.
# Inputs:
#   $1      reference ID or "none"
#   refs    work/references directory
# Outputs:
#   REF[], REF_REQ[]
load_reference() {
  local ref=$1 meta p pipe
  REF=() REF_REQ=()
  [[ $ref != none ]] || return 0
  pipe=$(awk '$1 == "pipeline" {print $2}' "$refs/$ref/info")
  [[ $pipe == toolchain || $pipe == sdk ]] ||
    die "reference $ref is not a toolchain/SDK build; make one with: POS_REFERENCE=none ./build run --new --toolchain"
  for meta in "$refs/$ref"/dest/*/pos/lib/pos/packages/*/meta; do
    [[ -f $meta ]] || continue
    p=$(basename "$(dirname "$meta")")
    [[ -n ${KIND[$p]:-} ]] || continue
    REF[$p]=1
    REF_REQ[$p]=$(awk '$1 == "requires" {$1 = ""; print}' "$meta" | xargs)
  done
  return 0
}

# The reference of the build; none for builds from before references.
# Inputs:
#   bdir    active build directory
build_reference() {
  local ref
  ref=$(build_info reference)
  echo "${ref:-none}"
}

# Store a complete toolchain build in the reference store (reference-dir)
# and mark it the default reference of new builds. The archive holds the
# build's info and the staging trees and debug info of what it built: the
# toolchain packages, and what they run on (glibc), which a pos build uses
# while it builds its own.
# Inputs:
#   [$1]    toolchain build ID (defaults to current_id)
cmd_reference() {
  local store out p t
  local -a trees=() debug=()
  id=${1:-$(current_id)} || die "no current build"
  bdir=$builds/$id
  [[ -f $bdir/info ]] || die "no build $id"
  [[ $(build_info pipeline) == toolchain ]] || die "build $id is not a toolchain build; only those are references"
  PIPELINE=toolchain
  store=$(config reference-dir)
  [[ -n $store ]] || die "reference-dir is not set (build.conf.dist)"
  [[ -d $store ]] || die "reference-dir $store does not exist"
  load_built
  local -a args
  mapfile -t args < <(pipeline_targets)
  targets_expand "${args[@]}"
  for t in "${TARGETS[@]}"; do
    [[ -n ${BUILT[$t]:-} ]] || die "build $id is not complete: $t is not built"
  done
  for p in "${PKGS[@]}"; do
    [[ -n ${BUILT[$p]:-} ]] || continue
    trees+=("dest/$p")
    [[ ! -d $bdir/debug/$p ]] || debug+=("debug/$p")
  done
  out=$store/pos-ref-$id.tar.zst
  if [[ ! -f $out ]]; then
    tar --zstd -cf "$out.tmp" -C "$bdir" info "${trees[@]}" "${debug[@]}"
    mv "$out.tmp" "$out"
  fi
  echo "$id" >"$store/default"
  echo "$out (${#trees[@]} packages), the default reference"
}
