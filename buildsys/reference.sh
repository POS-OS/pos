#!/usr/bin/env bash
# Reference build management. Sourced by buildsys/build.sh.
#
# A reference is a stored build, in work/references/<ref>, restored from the
# reference store (reference-dir). There are two kinds, by the pipeline of
# the build stored (BUILD.md "Reference builds"):
#
#   toolchain reference  a toolchain build: the toolchain packages. Its
#                        info names the pos reference it was built on
#   pos reference        a pos build: its core-libs packages, glibc and
#                        what links it. The toolchain runs on its glibc
#
# A toolchain build takes the compiler from a toolchain reference (or
# Fedora's, gcc-host, without one) and glibc from a pos reference. A pos
# build takes the toolchain from a toolchain reference and, until it has
# built its own, core-libs from a pos reference: by default the one the
# toolchain was built on, or a newer one. A pos build without a toolchain
# reference is the bootstrap: glibc, by Fedora's compiler, for the first
# pos reference.

declare TOOLCHAIN_REF=none POS_REF=none

# The reference the store marks the default of a kind, or nothing. Stores
# from before pos references mark the toolchain's as default.
# Inputs:
#   $1      toolchain or pos
#   config(reference-dir)
reference_default() {
  local store
  store=$(config reference-dir)
  [[ -n $store ]] || return 0
  if [[ -f $store/default-$1 ]]; then
    cat "$store/default-$1"
  elif [[ $1 == toolchain && -f $store/default ]]; then
    cat "$store/default"
  fi
}

# A field of a restored reference's info.
# Inputs:
#   $1      reference ID
#   $2      info key
#   refs    work/references directory
ref_info() {
  awk -v k="$2" '$1 == k {print $2}' "$refs/$1/info"
}

# The references a new build of PIPELINE uses, restored: the settings, else
# for a pos build the pos reference its toolchain reference was built on,
# else the store's defaults.
# Inputs:
#   PIPELINE, config(toolchain-reference, pos-reference, reference-dir)
# Outputs:
#   TOOLCHAIN_REF, POS_REF (reference IDs or none)
references_choose() {
  TOOLCHAIN_REF=$(config toolchain-reference)
  TOOLCHAIN_REF=${TOOLCHAIN_REF:-$(reference_default toolchain)}
  TOOLCHAIN_REF=${TOOLCHAIN_REF:-none}
  reference_restore "$TOOLCHAIN_REF"
  [[ $TOOLCHAIN_REF == none ]] || reference_kind "$TOOLCHAIN_REF" toolchain
  POS_REF=$(config pos-reference)
  if [[ -z $POS_REF && $PIPELINE == pos ]]; then
    # The bootstrap builds the first pos reference without one.
    [[ $TOOLCHAIN_REF == none ]] || POS_REF=$(ref_info "$TOOLCHAIN_REF" pos-reference)
  fi
  [[ -n $POS_REF || ($PIPELINE == pos && $TOOLCHAIN_REF == none) ]] ||
    POS_REF=$(reference_default pos)
  POS_REF=${POS_REF:-none}
  reference_restore "$POS_REF"
  [[ $POS_REF == none ]] || reference_kind "$POS_REF" pos
  if [[ $PIPELINE == toolchain ]]; then
    [[ $POS_REF != none ]] ||
      die "a toolchain build builds on the glibc of a pos reference; make one with:
  POS_TOOLCHAIN_REFERENCE=none ./build run --new glibc && ./build reference"
  elif [[ $TOOLCHAIN_REF != none ]]; then
    [[ $POS_REF != none ]] ||
      die "toolchain reference $TOOLCHAIN_REF names no pos reference; set pos-reference (POS_POS_REFERENCE)"
    pos_ref_check
  fi
}

# Die unless a restored reference is a build of the pipeline.
# Inputs:
#   $1      reference ID
#   $2      toolchain or pos
reference_kind() {
  local pipe
  pipe=$(ref_info "$1" pipeline)
  [[ ${pipe:-pos} == "$2" ]] || die "reference $1 is a ${pipe:-pos} build, not a $2 reference"
}

# The glibc version (major.minor) of a restored reference's glibc, or
# nothing when it has none.
# Inputs:
#   $1      reference ID
glibc_version() {
  local h=$refs/$1/dest/glibc/pos/include/features.h
  [[ -f $h ]] || return 0
  awk '$1 == "#define" && $2 == "__GLIBC__" {M = $3}
       $1 == "#define" && $2 == "__GLIBC_MINOR__" {m = $3}
       END {if (M != "") print M "." m}' "$h"
}

# Check that the pos reference of a pos build has a glibc at least as new as
# the one its toolchain was built on: the toolchain's programs need the
# symbol versions of that one. A toolchain reference from before pos
# references was built on its own glibc.
# Inputs:
#   TOOLCHAIN_REF, POS_REF
pos_ref_check() {
  local on have need
  on=$(ref_info "$TOOLCHAIN_REF" pos-reference)
  on=${on:-$TOOLCHAIN_REF}
  [[ $on != "$POS_REF" ]] || return 0
  reference_restore "$on"
  need=$(glibc_version "$on")
  have=$(glibc_version "$POS_REF")
  [[ -n $need ]] || die "reference $on, which toolchain reference $TOOLCHAIN_REF was built on, has no glibc"
  [[ -n $have ]] || die "pos reference $POS_REF has no glibc"
  [[ $(printf '%s\n' "$need" "$have" | sort -V | head -n1) == "$need" ]] ||
    die "pos reference $POS_REF has glibc $have; toolchain reference $TOOLCHAIN_REF needs $need or newer (built on $on)"
}

# Unpack a reference from the store into work/references/<ref>, unless it is
# there. The store is a directory; this is where a remote one would be
# fetched from. It holds pos-ref-<ref>.tar.zst archives, or reference
# directories ($store/$ref).
# Inputs:
#   $1      reference ID or "none"
#   refs    work/references directory
reference_restore() {
  local ref=$1 store archive
  [[ $ref != none && ! -f $refs/$ref/info ]] || return 0
  store=$(config reference-dir)
  [[ -n $store ]] || die "reference $ref is not in $refs, and reference-dir is not set"
  if [[ -f $store/$ref/info ]]; then
    rm -rf "$refs/$ref"
    ln -sfn "$store/$ref" "$refs/$ref"
    return 0
  fi
  archive=$store/pos-ref-$ref.tar.zst
  [[ -f $archive ]] || die "no reference $ref: missing pos-ref-$ref.tar.zst in $store"
  echo "restoring reference $ref from $archive" >&2
  rm -rf "$refs/$ref.tmp"
  mkdir -p "$refs/$ref.tmp"
  tar --zstd -xf "$archive" -C "$refs/$ref.tmp"
  mv "$refs/$ref.tmp" "$refs/$ref"
}

# The packages of the references the resolver may use, with the
# requirements they were built with (resolve.sh: REF, POSREF, REF_REQ):
# the toolchain packages of the toolchain reference, the pos packages of the
# pos reference. A toolchain reference from before pos references also
# holds glibc, which is not taken from it.
# Inputs:
#   TOOLCHAIN_REF, POS_REF, refs
# Outputs:
#   REF[], POSREF[], REF_REQ[]
load_references() {
  local ref from meta p
  REF=() POSREF=() REF_REQ=()
  for ref in "$TOOLCHAIN_REF" "$POS_REF"; do
    [[ $ref != none ]] || continue
    from=$(ref_info "$ref" pipeline)
    for meta in "$refs/$ref"/dest/*/pos/lib/pos/packages/*/meta; do
      [[ -f $meta ]] || continue
      p=$(basename "$(dirname "$meta")")
      [[ -n ${KIND[$p]:-} && ${PIPE[$p]} == "${from:-pos}" ]] || continue
      if [[ $from == toolchain ]]; then
        REF[$p]=1
      else
        POSREF[$p]=1
      fi
      REF_REQ[$p]=$(awk '$1 == "requires" {$1 = ""; print}' "$meta" | xargs)
    done
  done
  return 0
}

# The references of the build in bdir, restored: from its info. A build
# from before pos references has one reference, its toolchain's.
# Inputs:
#   bdir    active build directory
# Outputs:
#   TOOLCHAIN_REF, POS_REF
build_references() {
  TOOLCHAIN_REF=$(build_info toolchain-reference)
  TOOLCHAIN_REF=${TOOLCHAIN_REF:-$(build_info reference)}
  TOOLCHAIN_REF=${TOOLCHAIN_REF:-none}
  POS_REF=$(build_info pos-reference)
  POS_REF=${POS_REF:-none}
  reference_restore "$TOOLCHAIN_REF"
  reference_restore "$POS_REF"
}

# Store a build in the reference store (reference-dir) and mark it the
# default reference of its kind for new builds. The archive holds the
# build's info and the staging trees and debug info of what it stores: a
# complete toolchain build's toolchain packages, or a pos build's core-libs
# packages, which must include glibc.
# Inputs:
#   [$1]    build ID (defaults to current_id)
cmd_reference() {
  local store out p t kind
  local -a trees=() debug=() args=()
  local -A keep=()
  id=${1:-$(current_id)} || die "no current build"
  bdir=$builds/$id
  [[ -f $bdir/info ]] || die "no build $id"
  PIPELINE=$(build_info pipeline)
  PIPELINE=${PIPELINE:-pos}
  store=$(config reference-dir)
  [[ -n $store ]] || die "reference-dir is not set (build.conf.dist)"
  [[ -d $store ]] || die "reference-dir $store does not exist"
  load_built
  if [[ $PIPELINE == toolchain ]]; then
    kind=toolchain
    mapfile -t args < <(pipeline_targets)
    targets_expand "${args[@]}"
    for t in "${TARGETS[@]}"; do
      [[ -n ${BUILT[$t]:-} ]] || die "build $id is not complete: $t is not built"
    done
    for p in "${PKGS[@]}"; do
      ! in_pipeline "$p" || keep[$p]=1
    done
  else
    kind=pos
    [[ -n ${BUILT[glibc]:-} ]] || die "build $id has not built glibc; a pos reference is its core-libs"
    targets_expand core-libs
    for t in "${TARGETS[@]}"; do
      [[ -z ${BUILT[$t]:-} ]] || keep[$t]=1
    done
  fi
  for p in "${PKGS[@]}"; do
    [[ -n ${keep[$p]:-} && -n ${BUILT[$p]:-} ]] || continue
    trees+=("dest/$p")
    [[ ! -d $bdir/debug/$p ]] || debug+=("debug/$p")
  done
  out=$store/pos-ref-$id.tar.zst
  if [[ ! -f $out ]]; then
    tar --zstd -cf "$out.tmp" -C "$bdir" info "${trees[@]}" "${debug[@]}"
    mv "$out.tmp" "$out"
  fi
  echo "$id" >"$store/default-$kind"
  echo "$out (${#trees[@]} packages), the default $kind reference"
}
