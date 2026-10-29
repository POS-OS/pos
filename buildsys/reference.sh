#!/usr/bin/env bash
# Reference build management. Sourced by buildsys/build.sh.
#
# A reference is a stored build, in work/references/<ref>, restored from the
# reference store (reference-dir). Its kind is the pipeline of the build
# stored (BUILD.md "Reference builds"):
#
#   toolchain reference  a toolchain build: the toolchain packages. Its
#                        info names the pos reference it was built on
#   pos reference        a pos build: its core-libs packages, glibc and
#                        what links it. The toolchain runs on its glibc
#                        and builds with its kernel headers
#   extras reference     an extras build: the extras packages. Stored, not
#                        yet taken by builds
#
# A toolchain build takes the compiler from a toolchain reference (or
# Fedora's, gcc-host, without one) and glibc from a pos reference. A pos
# build takes the toolchain from a toolchain reference and, until it has
# built its own, core-libs from a pos reference: by default the one the
# toolchain was built on, or a newer one. A pos build without a toolchain
# reference is the bootstrap: glibc and linux-headers, by Fedora's
# compiler, for the first pos reference. An extras build takes the
# toolchain from a toolchain reference and core-libs from a pos reference,
# as a pos build does, and builds no package of either.

declare TOOLCHAIN_REF=none POS_REF=none

# The reference the store marks the default of a kind, or nothing. Stores
# from before pos references mark the toolchain's as default.
# Inputs:
#   $1      toolchain, pos or extras
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

# The prefix a restored reference's packages are installed in, from its
# info; /pos for references from before prefixes.
# Inputs:
#   $1      reference ID
#   refs    work/references directory
ref_prefix() {
  local p
  p=$(ref_info "$1" prefix)
  echo "${p:-/pos}"
}

# The references a new build of PIPELINE uses, restored: the settings (a
# build ID or a release, reference_named), else
# for a pos or extras build the pos reference its toolchain reference was
# built on, else the store's defaults.
# Inputs:
#   PIPELINE, config(toolchain-reference, pos-reference, reference-dir)
# Outputs:
#   TOOLCHAIN_REF, POS_REF (reference IDs or none)
references_choose() {
  TOOLCHAIN_REF=$(reference_named "$(config toolchain-reference)") || exit 1
  TOOLCHAIN_REF=${TOOLCHAIN_REF:-$(reference_default toolchain)}
  TOOLCHAIN_REF=${TOOLCHAIN_REF:-none}
  reference_restore "$TOOLCHAIN_REF" toolchain
  POS_REF=$(reference_named "$(config pos-reference)") || exit 1
  if [[ -z $POS_REF && $PIPELINE != toolchain ]]; then
    # The bootstrap builds the first pos reference without one.
    [[ $TOOLCHAIN_REF == none ]] || POS_REF=$(ref_info "$TOOLCHAIN_REF" pos-reference)
  fi
  [[ -n $POS_REF || ($PIPELINE == pos && $TOOLCHAIN_REF == none) ]] ||
    POS_REF=$(reference_default pos)
  POS_REF=${POS_REF:-none}
  reference_restore "$POS_REF" pos
  foreign_load "$TOOLCHAIN_REF"
  foreign_load "$POS_REF"
  case $PIPELINE in
    toolchain)
      [[ $POS_REF != none ]] ||
        die "a toolchain build builds on the glibc of a pos reference; make one with:
  POS_TOOLCHAIN_REFERENCE=none ./build run --new glibc && ./build reference"
      local p
      for p in $(toolchain_needs); do
        [[ -f $refs/$POS_REF/dest/$p/pos/lib/pos/packages/$p/meta ]] ||
          die "pos reference $POS_REF has no $p, which the toolchain builds on; store a pos build that has (./build reference <id>)"
      done
      ;;
    extras)
      # Fedora's compiler builds only from nothing; the extras are not part
      # of that chain.
      [[ $TOOLCHAIN_REF != none ]] ||
        die "an extras build builds with the toolchain of a toolchain reference; store one with pos-sdk's ./build reference"
      pos_ref_needed
      ;;
    pos)
      [[ $TOOLCHAIN_REF == none ]] || pos_ref_needed
      ;;
  esac
}

# Die unless a build with a toolchain reference has a pos reference its
# toolchain runs on (pos_ref_check).
# Inputs:
#   TOOLCHAIN_REF, POS_REF
pos_ref_needed() {
  [[ $POS_REF != none ]] ||
    die "toolchain reference $TOOLCHAIN_REF names no pos reference; set pos-reference (POS_POS_REFERENCE)"
  pos_ref_check
}

# The pos packages the toolchain packages require, which a toolchain build
# takes from its pos reference: glibc, linux-headers.
# Inputs:
#   PKGS, PIPE, REQ, PROVIDERS, KIND
toolchain_needs() {
  local p cap q
  for p in "${PKGS[@]}"; do
    [[ ${PIPE[$p]} == toolchain && (${KIND[$p]} == package || ${KIND[$p]} == output) ]] || continue
    for cap in ${REQ[$p]}; do
      for q in ${PROVIDERS[$cap]:-}; do
        [[ ${PIPE[$q]} == pos && ${KIND[$q]} == package ]] && echo "$q"
      done
    done
  done | sort -u
}

# Die unless a restored reference is a build of the pipeline.
# Inputs:
#   $1      reference ID
#   $2      toolchain, pos or extras
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
  [[ $on == "$TOOLCHAIN_REF" ]] || reference_restore "$on" pos
  need=$(glibc_version "$on")
  have=$(glibc_version "$POS_REF")
  [[ -n $need ]] || die "reference $on, which toolchain reference $TOOLCHAIN_REF was built on, has no glibc"
  [[ -n $have ]] || die "pos reference $POS_REF has no glibc"
  [[ $(printf '%s\n' "$need" "$have" | sort -V | head -n1) == "$need" ]] ||
    die "pos reference $POS_REF has glibc $have; toolchain reference $TOOLCHAIN_REF needs $need or newer (built on $on)"
}

# The store archive of a reference of a kind: pos-ref-<kind>-<ref>.tar.zst.
# Inputs:
#   $1      reference ID
#   $2      toolchain, pos or extras
reference_archive() {
  echo "pos-ref-$2-$1.tar.zst"
}

# The archive of a reference of a kind: in the reference store
# (reference-dir; pos-ref-<ref>.tar.zst from before the kinds had names of
# their own), else in a release of any project in the release library
# (release-dir), which holds its build's reference archive. Nothing when
# neither has it.
# Inputs:
#   $1      reference ID
#   $2      toolchain or pos
reference_find() {
  local name f store rels
  name=$(reference_archive "$1" "$2")
  store=$(config reference-dir)
  rels=$(config release-dir)
  for f in ${store:+"$store/$name" "$store/pos-ref-$1.tar.zst"} ${rels:+"$rels"/*/*/"$name"}; do
    [[ -f $f ]] && { echo "$f"; return 0; }
  done
  return 0
}

# The reference ID a setting names: a build ID, or a release as
# <project>/<release> in the release library (pos-sdk/1.0-1.main.20261029-2129),
# whose build that is.
# Inputs:
#   $1      the setting's value (an ID, <project>/<release>, none or nothing)
reference_named() {
  local info
  if [[ $1 == */* ]]; then
    info=$(config release-dir)/$1/info
    [[ -f $info ]] || die "no release $1 in the release library (release-dir)"
    awk '$1 == "id" {print $2}' "$info"
  else
    echo "$1"
  fi
}

# Unpack a reference of a kind into work/references/<ref>, unless it is
# there, and check that it is of that kind. It comes from the reference
# store, a directory holding reference archives or reference directories
# ($store/$ref), or from a release (reference_find); this is where a
# remote one would be fetched from.
# Inputs:
#   $1      reference ID or "none"
#   $2      toolchain or pos
#   refs    work/references directory
reference_restore() {
  local ref=$1 kind=$2 store archive
  [[ $ref != none ]] || return 0
  if [[ ! -f $refs/$ref/info ]]; then
    store=$(config reference-dir)
    if [[ -n $store && -f $store/$ref/info ]]; then
      rm -rf "$refs/$ref"
      ln -sfn "$store/$ref" "$refs/$ref"
    else
      archive=$(reference_find "$ref" "$kind")
      [[ -n $archive ]] ||
        die "no $kind reference $ref: no $(reference_archive "$ref" "$kind") in the reference store (reference-dir) or a release (release-dir)"
      echo "restoring reference $ref from $archive" >&2
      rm -rf "$refs/$ref.tmp"
      mkdir -p "$refs/$ref.tmp"
      tar --zstd -xf "$archive" -C "$refs/$ref.tmp"
      mv "$refs/$ref.tmp" "$refs/$ref"
    fi
  fi
  reference_kind "$ref" "$kind"
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
    for meta in "$refs/$ref"/dest/*"$(ref_prefix "$ref")"/lib/pos/packages/*/meta; do
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
  reference_restore "$TOOLCHAIN_REF" toolchain
  reference_restore "$POS_REF" pos
  foreign_load "$TOOLCHAIN_REF"
  foreign_load "$POS_REF"
}

# The reference archive of a build: its info and the staging trees and
# debug info of what a reference of it holds: a complete toolchain or
# extras build's packages, or a pos build's core-libs packages, which must
# include what the toolchain packages require of pos (glibc,
# linux-headers). Written as <dir>/pos-ref-<kind>-<id>.tar.zst
# (reference_archive), for the reference store and for a release.
# Inputs:
#   $1      directory to write the archive into
#   id, bdir
# Outputs:
#   REF_OUT (the archive), REF_KIND (the pipeline), REF_COUNT (packages)
reference_pack() {
  local p t
  local -a trees=() debug=() args=()
  local -A keep=()
  PIPELINE=$(build_info pipeline)
  PIPELINE=${PIPELINE:-pos}
  PREFIX=$(build_prefix)
  load_built
  if [[ $PIPELINE != pos ]]; then
    REF_KIND=$PIPELINE
    mapfile -t args < <(pipeline_targets)
    targets_expand "${args[@]}"
    for t in "${TARGETS[@]}"; do
      [[ -n ${BUILT[$t]:-} ]] || die "build $id is not complete: $t is not built"
    done
    for p in "${PKGS[@]}"; do
      ! in_pipeline "$p" || keep[$p]=1
    done
  else
    REF_KIND=pos
    targets_expand core-libs
    for p in $(toolchain_needs); do
      [[ -n ${BUILT[$p]:-} ]] ||
        die "build $id has not built $p, which the toolchain builds on; a pos reference is its core-libs"
    done
    for t in "${TARGETS[@]}"; do
      [[ -z ${BUILT[$t]:-} ]] || keep[$t]=1
    done
  fi
  for p in "${PKGS[@]}"; do
    [[ -n ${keep[$p]:-} && -n ${BUILT[$p]:-} ]] || continue
    trees+=("dest/$p")
    [[ ! -d $bdir/debug/$p ]] || debug+=("debug/$p")
  done
  REF_OUT=$1/$(reference_archive "$id" "$REF_KIND")
  REF_COUNT=${#trees[@]}
  tar --zstd -cf "$REF_OUT.tmp" -C "$bdir" info "${trees[@]}" "${debug[@]}"
  mv "$REF_OUT.tmp" "$REF_OUT"
}

# Store a build in the reference store (reference-dir) and mark it the
# default reference of its kind for new builds (reference_pack). Written
# again when it is there: what a build stores follows the checkout's
# stages, which may have changed since. A copy restored from the archive
# before goes, so the next build restores this one.
# Inputs:
#   [$1]    build ID (defaults to current_id)
cmd_reference() {
  local store
  id=${1:-$(current_id)} || die "no current build"
  bdir=$builds/$id
  [[ -f $bdir/info ]] || die "no build $id"
  store=$(config reference-dir)
  [[ -n $store ]] || die "reference-dir is not set (build.conf.dist)"
  [[ -d $store ]] || die "reference-dir $store does not exist"
  reference_pack "$store"
  rm -rf "${refs:?}/$id"
  echo "$id" >"$store/default-$REF_KIND"
  echo "$REF_OUT ($REF_COUNT packages), the default $REF_KIND reference"
}
