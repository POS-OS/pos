#!/usr/bin/env bash
# Build outputs: what a build makes of its assembled stages (images, disks,
# RPM packages). Sourced by buildsys/build.sh, which makes them; run as a
# script, it makes one in a build container.
#
# Every directory in outputs/ is an output, with a meta file of "key
# value..." lines (repeated keys accumulate; # starts a comment) and
# output.sh, its recipe:
#
#   requires       stages and outputs it is made from: a stage of the
#                  build once assembled, an output once made. The stages
#                  are extracted in the order given
#   host-requires  Fedora packages its steps need in the build's tools
#                  image
#   tag            its name in podman (output-plugins.d/podman.sh)
#   path-priority  pos or host: whose bin directories come first in PATH
#                  when imported into podman
#
# output.sh defines one or both phases:
#
#   output()       runs in a container of the build's tools image, as the
#                  container's root, with network; it sees the recipes
#                  (buildsys, outputs, the stage lists) and the build directory
#   output_host()  runs on the host after it, for what needs the host's
#                  podman (podman images, the VM of disk checks)
#
# Both phases see the helpers below, the functions of the plugins
# (output-plugins.d/*.sh) and these variables:
#
#   base      the POS checkout
#   bdir      the build directory; id is the build ID
#   output    the output's name
#   stages    the stages it requires, in order (array)
#   stem      the part of artifact names that names the build (buildinfo.sh)
#   evr       the version-release of the build's RPM packages
#   work      a scratch directory of the output, $bdir/output/<output>; the
#             container phase empties it before output() and removes it
#             after, as root: what it holds may belong to users an image
#             creates, which only the container's root can remove
#
# An output is recorded made (made/output-<output>, see step_made) when
# both phases succeed, unchecked when output_host() sets OUTPUT_STATUS
# to unchecked.

declare -a OUTPUTS=()
declare -A OUT_REQ=() OUT_HREQ=()

# --- helpers for recipes and plugins -------------------------------------

# The definition directory of an output.
# Inputs:
#   [$1]      output name (default: the output being made)
#   base, output
output_dir() {
  echo "$base/outputs/${1:-$output}"
}

# The path of an artifact of the output: <bdir>/pos-<output>-<stem>.<ext>.
# Inputs:
#   $1        file name extension (tar.zst, qcow2, packages)
#   [$2]      output name (default: the output being made)
#   bdir, stem, output
output_file() {
  echo "$bdir/pos-${2:-$output}-$stem.$1"
}

# The values of a key in an output's meta, repeated lines joined.
# Inputs:
#   $1    output name
#   $2    meta key
#   base
output_meta() {
  sed -e 's/#.*//' "$base/outputs/$1/meta" | awk -v k="$2" '$1 == k {$1 = ""; print}' | xargs
}

# --- internal ------------------------------------------------------------

# Set up the variables of an output and source the plugins and its recipe.
# Inputs:
#   $1    output name
#   base, bdir
# Outputs:
#   output, stages[], stem, evr, work, id; the recipe's output() and
#   output_host()
_output_setup() {
  local r f
  output=$1
  id=$(basename "$bdir")
  stem=$(build_stem "$bdir")
  evr=$(rpm_evr "$bdir")
  work=$bdir/output/$output
  stages=()
  for r in $(output_meta "$output" requires); do
    [[ ! -f $base/pos/$r/stage ]] || stages+=("$r")
  done
  for f in "$base"/buildsys/output-plugins.d/*.sh; do
    # shellcheck source=/dev/null
    source "$f"
  done
  # shellcheck source=/dev/null
  source "$base/outputs/$output/output.sh"
}

# Load every outputs/*/meta into OUTPUTS, OUT_REQ and OUT_HREQ, and check
# them: known keys, each requirement a stage or an output, and a recipe
# with a phase.
# Inputs:
#   base
# Outputs:
#   OUTPUTS[], OUT_REQ[], OUT_HREQ[]
outputs_load() {
  local dir o key r
  for dir in "$base"/outputs/*/; do
    o=$(basename "$dir")
    [[ -f $dir/meta ]] || die "outputs/$o: missing meta"
    [[ -f $dir/output.sh ]] || die "outputs/$o: missing output.sh"
    grep -Eq '^(output|output_host)\(\)' "$dir/output.sh" ||
      die "outputs/$o/output.sh: defines neither output() nor output_host()"
    for key in $(sed -e 's/#.*//' "$dir/meta" | awk '{print $1}'); do
      case $key in
        requires|host-requires|tag|path-priority) ;;
        *) die "outputs/$o/meta: unknown key: $key" ;;
      esac
    done
    OUTPUTS+=("$o")
    OUT_REQ[$o]=$(output_meta "$o" requires)
    OUT_HREQ[$o]=$(output_meta "$o" host-requires)
  done
  for o in "${OUTPUTS[@]}"; do
    for r in ${OUT_REQ[$o]}; do
      [[ -f $(stage_file "$r") || -d $base/outputs/$r ]] ||
        die "outputs/$o/meta: requires $r, which is neither a stage nor an output"
    done
  done
}

# The outputs that can be made from the given stages: those whose
# requirements are among them, or outputs that can be. An output in a
# requirement cycle never can.
# Inputs:
#   $@    assembled stage names
#   OUTPUTS, OUT_REQ
outputs_of() {
  local o r changed=1
  local -A can=()
  while [[ -n $changed ]]; do
    changed=
    for o in "${OUTPUTS[@]}"; do
      [[ -z ${can[$o]:-} ]] || continue
      for r in ${OUT_REQ[$o]}; do
        if [[ -n ${OUT_REQ[$r]+set} ]]; then
          [[ -n ${can[$r]:-} ]] || continue 2
        else
          [[ " $* " == *" $r "* ]] || continue 2
        fi
      done
      can[$o]=1
      changed=1
    done
  done
  for o in "${OUTPUTS[@]}"; do
    [[ -z ${can[$o]:-} ]] || echo "$o"
  done
}

# Return 0 when every requirement of an output is made in the build: its
# stages assembled, its outputs made.
# Inputs:
#   $1    output name
#   bdir, OUT_REQ
output_ready() {
  local r
  for r in ${OUT_REQ[$1]}; do
    if [[ -n ${OUT_REQ[$r]+set} ]]; then
      [[ -f $bdir/made/output-$r ]] || return 1
    else
      [[ -f $bdir/made/stage-$r ]] || return 1
    fi
  done
}

# Make an output: output() in a build container, then output_host() here,
# in a subshell, so the recipe's functions and variables stay in it.
# outputs_run has dropped its record (step_start).
# Inputs:
#   $1        output name
#   base, bdir, id, CHECKS
output_make() {
  (
    _output_setup "$1"
    OUTPUT_STATUS=
    if declare -F output >/dev/null; then
      local s
      local -a stage_mounts=()
      for s in $(all_stages); do
        stage_mounts+=(ro:"$(stage_file "$s")")
      done
      step_run "output-$output" net root ro:"$base/buildsys" ro:"$base/outputs" "${stage_mounts[@]}" rw:"$bdir" -- \
        bash "$(host_path "$base/buildsys/outputs.sh")" "$(host_path "$bdir")" "$output"
    fi
    if declare -F output_host >/dev/null; then
      output_host
    fi
    step_made "output-$output" ${OUTPUT_STATUS:+"$OUTPUT_STATUS"}
  )
}

# Make outputs, each as soon as its requirements are made, at the same
# time as the others that are ready; each logs to logs/output-<output>.log.
# After a failure no more are started; the running ones finish.
# Inputs:
#   $@    output names
#   bdir, OUT_REQ
outputs_run() {
  local o pid log
  local -a pending=("$@") later failed=()
  local -A running=()
  for o in "$@"; do
    step_start "output-$o"
  done
  mkdir -p "$bdir/logs"
  while ((${#pending[@]} + ${#running[@]})); do
    later=()
    for o in "${pending[@]}"; do
      if ((${#failed[@]} == 0)) && output_ready "$o"; then
        log=$bdir/logs/output-$o.log
        echo "=== output $o: started, log $log ==="
        title "output $o"
        output_make "$o" >"$log" 2>&1 &
        running[$!]=$o
      else
        later+=("$o")
      fi
    done
    pending=("${later[@]}")
    if ((${#running[@]} == 0)); then
      ((${#failed[@]})) || die "cannot make ${pending[*]}: requirements not made in build $id"
      break
    fi
    if wait -n -p pid "${!running[@]}"; then
      echo "=== output ${running[$pid]}: done ==="
    else
      failed+=("${running[$pid]}")
      echo "=== output ${running[$pid]}: failed, see $bdir/logs/output-${running[$pid]}.log ===" >&2
    fi
    unset "running[$pid]"
  done
  ((${#failed[@]} == 0)) || die "outputs failed: ${failed[*]}${pending[*]:+; not made: ${pending[*]}}"
}

# CLI command: make outputs of the current build again: the given ones, or
# every output its assembled stages can make. They take what they require
# from the build.
# Inputs:
#   $@    [--no-checks] [<output>...]
cmd_output() {
  local o s
  [[ ${1:-} != --no-checks ]] || { CHECKS=no; shift; }
  local -a args=("$@") stages=()
  id=$(current_id) || die "no current build"
  bdir=$builds/$id
  [[ -n $(build_info tools-image) ]] ||
    die "build $id builds in toolboxes, which this buildsys no longer does; start another with run --new"
  build_versioned "$bdir"
  if ((${#args[@]} == 0)); then
    for s in $(all_stages); do
      [[ ! -f $bdir/made/stage-$s ]] || stages+=("$s")
    done
    mapfile -t args < <(outputs_of "${stages[@]}")
  fi
  for o in "${args[@]}"; do
    [[ -n ${OUT_REQ[$o]+set} ]] || die "not an output: $o"
  done
  tools_ensure
  title_init
  outputs_run "${args[@]}"
}

# Run as a script, in a build container (output_make): make the output's
# output() phase.
#   outputs.sh <build dir> <output>
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -euo pipefail
  export LC_ALL=C
  [[ -f /run/.containerenv && ! -f /run/.toolboxenv && $(id -u) == 0 ]] || {
    echo "outputs.sh must run as root of a build container (./build output)" >&2
    exit 1
  }
  die() {
    echo "$*" >&2
    exit 1
  }
  base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
  # shellcheck source=buildinfo.sh
  source "$base/buildsys/buildinfo.sh"
  bdir=${1:?usage: outputs.sh <build dir> <output>}
  _output_setup "${2:?usage: outputs.sh <build dir> <output>}"
  rm -rf "$work"
  mkdir -p "$work"
  output
  rm -rf "$work"
fi
