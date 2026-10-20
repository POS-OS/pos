#!/usr/bin/env bash
# Package metadata and dependency resolution. Sourced by buildsys/build.sh.
#
# The checkout's pos/ is divided into trees, pos/<tree>, each with any of
# packages/<package>/ (recipes), src/<source> with src/<source>.upstream
# (synced upstream sources) and stage (the member list of the stage
# <tree>). Package names are unique across trees, and so are source names.
#
# Every package directory has a meta file of "key value..." lines.
# Repeated keys accumulate; # starts a comment.
#
#   requires        capabilities needed at run time; installed with the
#                   package, so they are part of every build that uses it
#   build-requires  capabilities needed only to build the package
#   host-requires   Fedora packages dnf installs into the build toolbox
#   prepare-requires  Fedora packages for preparing the package's source
#                   (<source>'s package directory, prepare.sh) in the
#                   prepare toolbox
#   provides        extra capabilities; every package provides its own name
#   obsoletes       packages this one replaces. Where both are available,
#                   the obsoleting package is the one chosen
#   source          source tree (default: the package name); its prepare
#                   recipe is prepare.sh of the package named after it
#   with-sources    further source trees the build copies into its own,
#                   each as a directory named after the source (gcc builds
#                   gmp, mpfr and mpc in its tree)
#
# A source is the package's own tree's or common's; a source of another
# tree is named <tree>/<source> (gcc: core-libs/gmp), so what crosses
# trees shows in the meta.
#   outputs         further packages the build produces (kind output)
#   output-of       the package whose build produces this one
#   pipeline        pos (default) or toolchain: the build that builds the
#                   package (see below). An output is in its main
#                   package's pipeline
#   kind            package (default): built by build.sh
#                   output: produced by another package's build; installed
#                   and released like a package, never built on its own
#                   host: nothing to build; stands for the host-requires
#                   installed by dnf
#                   profile: nothing to build or install; a build setup
#                   that recipes require
#                   source: nothing to build; holds the prepare recipe of
#                   a source other packages build from (with-sources)
#
# A package directory may also have env.sh. pkg_setup sources it in every
# build whose resolved environment contains the package.
#
# A capability is satisfied by any available package that provides it: a
# package or output built in the current build, or a host or profile
# package. When several are
# available, those obsoleted by another candidate are dropped; more than one
# left is an error.
#
# A build is in one of two pipelines (PIPELINE), and builds only the
# packages of its own. A toolchain build builds the toolchain packages; a
# pos build builds everything else. Each takes what the other builds from
# a reference (reference.sh): the toolchain from a toolchain reference
# (REF: its packages), glibc and the rest of core-libs from a pos reference
# (POSREF). A host or profile package is not available where a toolchain
# reference package obsoletes it, or a target of the run that does not
# itself require it: gcc-host and host-linux-headers, Fedora's compiler
# and kernel headers, stand in for gcc and linux-headers only in a build
# without a toolchain reference, and gcc-host for gcc in the toolchain
# build that builds gcc with it.
#
# Where nothing available provides a capability, a build falls back to a
# reference's copy of a package: a toolchain package if the capability is
# a stand-in one (provided by a package another obsoletes: the
# reference's gcc stands in for gcc-host) or, in a pos build, if no target
# of the run provides it (it is not being built); a pos package in a
# toolchain build, or in a pos build if no target of the run provides it.
# In ENV it is <name>@ref (toolchain reference) or <name>@pos (pos
# reference). Its own requirements are those it was built with (REF_REQ),
# and are met by this build's packages where they are built, otherwise by
# the references', whether or not they are targets: the reference's gcc
# builds glibc, which gcc itself requires.

declare -a PKGS=()
declare -A KIND=() REQ=() BREQ=() HREQ=() PREQ=() PROV=() OBS=() SRC=() WSRC=() OUTS=() PARENT=()
declare -A PIPE=() PKGDIR=() SRCPATH=() SRCREFS=()
declare -A PROVIDERS=() BOOTCAP=() TPROV=()
declare -A BUILT=() REF=() POSREF=() REF_REQ=()
declare -a TARGETS=()
PIPELINE=pos

die() {
  echo "$*" >&2
  exit 1
}

# The tree a checkout path under pos/ is in.
# Inputs:
#   $1    path relative to base (pos/<tree>/...)
tree_of() {
  local t=${1#pos/}
  echo "${t%%/*}"
}

# The member list of a stage.
# Inputs:
#   $1    stage name
stage_file() {
  echo "$base/pos/$1/stage"
}

# Find the source trees, pos/<tree>/src/<source>, and those whose
# .upstream is committed before the tree is synced.
# Inputs:
#   base    path to the POS checkout
# Outputs:
#   SRCPATH[<source>]   its path relative to base
sources_load() {
  local f s rel
  for f in "$base"/pos/*/src/*; do
    rel=${f#"$base"/}
    rel=${rel%.upstream}
    s=${rel##*/}
    [[ -z ${SRCPATH[$s]:-} || ${SRCPATH[$s]} == "$rel" ]] ||
      die "source $s is in two trees: ${SRCPATH[$s]} and $rel"
    SRCPATH[$s]=$rel
  done
}

# Load the meta file of every package directory into the resolver tables,
# and the sources (sources_load). A source a package names that is not in
# the checkout gets the path it would have.
# Inputs:
#   base    path to the POS checkout
# Outputs (arrays/maps populated):
#   PKGS, PKGDIR, KIND, REQ, BREQ, HREQ, PREQ, PROV, OBS, SRC, WSRC,
#   SRCREFS (source and with-sources as written), SRCPATH, OUTS, PARENT,
#   PIPE, PROVIDERS, BOOTCAP
meta_load() {
  local dir p key vals line r
  sources_load
  for dir in "$base"/pos/*/packages/*/; do
    dir=${dir%/}
    p=${dir##*/}
    [[ -z ${PKGDIR[$p]:-} ]] || die "package $p is in two trees: ${PKGDIR[$p]} and ${dir#"$base"/}"
    PKGDIR[$p]=${dir#"$base"/}
    [[ -f $dir/meta ]] || die "${PKGDIR[$p]}: missing meta"
    PKGS+=("$p")
    KIND[$p]=package REQ[$p]= BREQ[$p]= HREQ[$p]= PREQ[$p]= PROV[$p]=$p OBS[$p]= SRC[$p]=$p
    WSRC[$p]= OUTS[$p]= PARENT[$p]= PIPE[$p]=pos
    while read -r line; do
      line=${line%%#*}
      read -r key vals <<<"$line"
      [[ -z $key ]] && continue
      case $key in
        requires) REQ[$p]+=" $vals" ;;
        build-requires) BREQ[$p]+=" $vals" ;;
        host-requires) HREQ[$p]+=" $vals" ;;
        prepare-requires) PREQ[$p]+=" $vals" ;;
        provides) PROV[$p]+=" $vals" ;;
        obsoletes) OBS[$p]+=" $vals" ;;
        source) SRC[$p]=$vals ;;
        with-sources) WSRC[$p]+=" $vals" ;;
        pipeline) PIPE[$p]=$vals ;;
        kind) KIND[$p]=$vals ;;
        outputs) OUTS[$p]+=" $vals" ;;
        output-of) PARENT[$p]=$vals ;;
        *) die "${PKGDIR[$p]}/meta: unknown key: $key" ;;
      esac
    done <"$dir/meta"
    if [[ ${KIND[$p]} == package ]]; then
      # Everything built gets the common host tools.
      BREQ[$p]+=" host-base"
    fi
    if [[ ${KIND[$p]} == package || ${KIND[$p]} == source ]]; then
      SRCREFS[$p]="${SRC[$p]} ${WSRC[$p]}"
      SRC[$p]=${SRC[$p]##*/}
      WSRC[$p]=$(for r in ${WSRC[$p]}; do echo "${r##*/}"; done | xargs)
      for r in ${SRCREFS[$p]}; do
        [[ $r == */* ]] || r=$(tree_of "${PKGDIR[$p]}")/$r
        [[ -n ${SRCPATH[${r##*/}]:-} ]] || SRCPATH[${r##*/}]=pos/${r%/*}/src/${r##*/}
      done
    fi
  done
  mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | sort)
  local cap q
  for p in "${PKGS[@]}"; do
    [[ ${KIND[$p]} != output ]] || PIPE[$p]=${PIPE[${PARENT[$p]}]:-pos}
    for cap in ${PROV[$p]}; do
      PROVIDERS[$cap]+=" $p"
    done
    for q in ${OBS[$p]}; do
      for cap in ${PROV[$q]:-}; do
        BOOTCAP[$cap]=1
      done
    done
  done
}

# Validate all loaded package metadata for missing recipes, broken output-of
# links, missing capability providers, and incomplete obsoletes coverage.
# Inputs:
#   base, PKGS, PKGDIR, KIND, PARENT, OUTS, REQ, BREQ, PROVIDERS, PIPE, WSRC,
#   SRCREFS, SRCPATH, OBS, PROV
meta_validate() {
  local p m cap q t err=0
  local -A required=()
  for p in "${PKGS[@]}"; do
    m=${PKGDIR[$p]}/meta
    case ${KIND[$p]} in
      package) [[ -f $base/${PKGDIR[$p]}/build.sh ]] || { echo "${PKGDIR[$p]}: missing build.sh" >&2; err=1; } ;;
      output)
        q=${PARENT[$p]}
        if [[ ${KIND[$q]:-} != package || " ${OUTS[$q]} " != *" $p "* ]]; then
          echo "$m: output-of $q, which does not list it in outputs" >&2
          err=1
        fi
        ;;
      host|profile|source) ;;
      *) echo "$m: unknown kind: ${KIND[$p]}" >&2; err=1 ;;
    esac
    for cap in ${REQ[$p]} ${BREQ[$p]}; do
      required[$cap]=1
      if [[ -z ${PROVIDERS[$cap]:-} ]]; then
        echo "$m: nothing provides $cap" >&2
        err=1
      fi
    done
    case ${PIPE[$p]} in
      pos|toolchain) ;;
      *) echo "$m: unknown pipeline: ${PIPE[$p]}" >&2; err=1 ;;
    esac
    for q in ${WSRC[$p]}; do
      if [[ ! -d $base/${SRCPATH[$q]} ]]; then
        echo "$m: with-sources $q: no ${SRCPATH[$q]}" >&2
        err=1
      fi
    done
    for q in ${SRCREFS[$p]:-}; do
      t=$(tree_of "${SRCPATH[${q##*/}]}")
      if [[ $q == */* && ${q%/*} != "$t" ]]; then
        echo "$m: source $q: not in pos/${q%/*}/src; it is ${SRCPATH[${q##*/}]}" >&2
        err=1
      elif [[ $q != */* && $t != "$(tree_of "${PKGDIR[$p]}")" && $t != common ]]; then
        echo "$m: source $q is in another tree: name it $t/$q" >&2
        err=1
      fi
    done
    for q in ${OUTS[$p]}; do
      if [[ ${KIND[$q]:-} != output || ${PARENT[$q]} != "$p" ]]; then
        echo "$m: output $q is not kind output with output-of $p" >&2
        err=1
      fi
    done
    for q in ${OBS[$p]}; do
      if [[ -z ${KIND[$q]:-} ]]; then
        echo "$m: obsoletes unknown package $q" >&2
        err=1
      fi
    done
  done
  # An obsoleting package takes over every capability that the obsoleted
  # one is required for; otherwise preferring it would leave those unmet.
  for p in "${PKGS[@]}"; do
    for q in ${OBS[$p]}; do
      [[ -n ${KIND[$q]:-} ]] || continue
      for cap in ${PROV[$q]}; do
        if [[ -n ${required[$cap]:-} && " ${PROV[$p]} " != *" $cap "* ]]; then
          echo "${PKGDIR[$p]}/meta: obsoletes $q but does not provide $cap" >&2
          err=1
        fi
      done
    done
  done
  return $err
}

# Built packages, and host and profile packages that no toolchain
# reference package obsoletes, nor a target of the run that does not
# require what they provide (see the top).
# Inputs:
#   $1    package name
#   REF, TARGETS
available() {
  case ${KIND[$1]} in
    host|profile) ! obsoleted_by_any "$1" "${!REF[@]}" && ! obsoleted_by_target "$1" ;;
    *) [[ -n ${BUILT[$1]:-} ]] ;;
  esac
}

# True when a target of the run obsoletes p and its build does not require
# a capability p provides: gcc, built with gcc-host, does.
# Inputs:
#   $1        package name p
#   TARGETS
obsoleted_by_target() {
  local p=$1 t b cap
  for t in "${TARGETS[@]}"; do
    obsoleted_by_any "$p" "$t" || continue
    b=$(build_of "$t")
    for cap in ${BREQ[$b]} ${REQ[$b]}; do
      [[ " ${PROV[$p]} " != *" $cap "* ]] || continue 2
    done
    return 0
  done
  return 1
}

# Whether the build's pipeline builds a package.
# Inputs:
#   $1          package name
#   PIPELINE    active pipeline name
in_pipeline() {
  [[ ${PIPE[$1]} == "$PIPELINE" ]]
}

# The package whose build produces p.
# Inputs:
#   $1    package or output name
build_of() {
  if [[ ${KIND[$1]} == output ]]; then
    echo "${PARENT[$1]}"
  else
    echo "$1"
  fi
}

# Capabilities a build provides: the package's and its outputs'.
# Inputs:
#   $1    package name
self_provides() {
  local p=$1 o
  echo "${PROV[$p]}"
  for o in ${OUTS[$p]}; do
    echo "${PROV[$o]}"
  done
}

# True when one of the packages q (or, for builds, their outputs) obsoletes p.
# Inputs:
#   $1       package name p to test
#   ${@:2}   candidate package names q
obsoleted_by_any() {
  local p=$1 q o
  shift
  for q in "$@"; do
    [[ $q == "$p" ]] && continue
    for o in "$q" ${OUTS[$q]:-}; do
      [[ " ${OBS[$o]} " == *" $p "* ]] && return 0
    done
  done
  return 1
}

# Set PROVIDER to the available provider of a capability. Returns 1 when
# none is available. Dies when the choice is ambiguous. With ref, the
# capability is a requirement of a reference package (see the top).
# Inputs:
#   $1      capability name
#   [$2]    non-empty when resolving a requirement of a reference package
# Outputs:
#   PROVIDER (shell variable)
provider() {
  local cap=$1 ref=${2:-} p
  local -a cands=() chosen=()
  for p in ${PROVIDERS[$cap]:-}; do
    available "$p" && cands+=("$p")
  done
  for p in "${cands[@]}"; do
    obsoleted_by_any "$p" "${cands[@]}" || chosen+=("$p")
  done
  case ${#chosen[@]} in
    0) provider_ref "$cap" "$ref" ;;
    1) PROVIDER=${chosen[0]} ;;
    *) die "ambiguous providers of $cap: ${chosen[*]} (add obsoletes to pick one)" ;;
  esac
}

# A reference's copy of a provider, as PROVIDER=<name>@ref or <name>@pos
# (see the top).
# Inputs:
#   $1    capability name
#   $2    non-empty when resolving a requirement of a reference package
# Outputs:
#   PROVIDER (shell variable, set to <name>@ref or <name>@pos when found)
provider_ref() {
  local cap=$1 ref=$2 p
  for p in ${PROVIDERS[$cap]:-}; do
    if [[ -n ${REF[$p]:-} ]]; then
      [[ -n $ref || -n ${BOOTCAP[$cap]:-} ]] ||
        [[ $PIPELINE == pos && -z ${TPROV[$cap]:-} ]] || continue
      PROVIDER=$p@ref
      return 0
    elif [[ -n ${POSREF[$p]:-} ]]; then
      [[ -n $ref || $PIPELINE == toolchain || -z ${TPROV[$cap]:-} ]] || continue
      PROVIDER=$p@pos
      return 0
    fi
  done
  return 1
}

# Return 0 if an environment entry is satisfied from a reference build
# (<pkg>@ref or <pkg>@pos).
# Inputs:
#   $1    environment entry
is_ref() {
  [[ $1 == *@ref || $1 == *@pos ]]
}

# Resolve the build environment of a package: its requirements and,
# recursively, the run-time requirements of each provider chosen. A
# requirement the build itself provides (gcc requires its own output
# gcc-runtime) is installed with the package, not needed to build it.
# Reached through another package's requirements, it is needed (systemd
# links util-linux's libmount, which links libsystemd), and the reference's
# copy is used, as in a new build, where the package is not built yet. Sets
# ENV (sorted package names) and MISSING (capabilities with no available
# provider). Returns 1 when anything is missing.
# Inputs:
#   $1    package name
# Outputs:
#   ENV (array of resolved package names), MISSING (array of unresolved capabilities)
env_of() {
  local p=$1 cap entry ref q
  local -a queue=()
  local -A seen=() inenv=()
  local self
  self=" $(self_provides "$p" | xargs) "
  for cap in ${BREQ[$p]} ${REQ[$p]}; do
    [[ $self == *" $cap "* ]] || queue+=("$cap")
  done
  ENV=() MISSING=()
  # An entry is a capability, or ref:<capability> for a requirement of a
  # reference package.
  while ((${#queue[@]})); do
    entry=${queue[0]}
    queue=("${queue[@]:1}")
    [[ -n ${seen[$entry]:-} ]] && continue
    seen[$entry]=1
    cap=${entry#ref:}
    ref=
    [[ $entry == ref:* || $self == *" $cap "* ]] && ref=1
    if ! provider "$cap" "$ref"; then
      MISSING+=("$cap")
      continue
    fi
    [[ -n ${inenv[$PROVIDER]:-} ]] && continue
    inenv[$PROVIDER]=1
    if is_ref "$PROVIDER"; then
      for q in ${REF_REQ[${PROVIDER%@*}]:-}; do
        queue+=("ref:$q")
      done
    else
      queue+=(${REQ[$PROVIDER]})
    fi
  done
  mapfile -t ENV < <(printf '%s\n' "${!inenv[@]}" | sed '/^$/d' | sort)
  ((${#MISSING[@]} == 0))
}

# Check whether any package in the resolved ENV[] provides a capability.
# Inputs:
#   $1     capability name
#   ENV    resolved environment array from env_of
env_provides() {
  local cap=$1 p
  for p in "${ENV[@]}"; do
    [[ " ${PROV[${p%@*}]} " == *" $cap "* ]] && return 0
  done
  return 1
}

# Packages in the environment that set up the build (buildsys/pkg.sh).
# Inputs:
#   ENV    resolved environment array from env_of
env_scripts() {
  local p
  for p in "${ENV[@]}"; do
    p=${p%@*}
    [[ -f $base/${PKGDIR[$p]}/env.sh ]] && echo "$p"
  done
  return 0
}

# Expand target names (stages or packages) into TARGETS (package names),
# and TPROV, the capabilities their builds provide. A pos build leaves out
# the toolchain packages of a stage, which its reference has; a toolchain
# build has toolchain packages only.
# Inputs:
#   $@    stage names and/or package names
# Outputs:
#   TARGETS (sorted array of package names), TPROV (map of capabilities provided by TARGETS)
targets_expand() {
  local t p
  local -A set=()
  for t in "$@"; do
    if [[ -f $(stage_file "$t") ]]; then
      [[ $PIPELINE == pos ]] || die "$t: a toolchain build builds toolchain packages, not stages"
      while read -r p; do
        p=${p%%#*}
        p=${p//[[:space:]]/}
        [[ -z $p ]] && continue
        case ${KIND[$p]:-} in
          package|output) ;;
          '') die "pos/$t/stage: unknown package $p" ;;
          *) die "pos/$t/stage: $p is not a package (kind ${KIND[$p]})" ;;
        esac
        in_pipeline "$p" && set[$p]=1
      done <"$(stage_file "$t")"
    elif [[ -n ${KIND[$t]:-} ]]; then
      in_pipeline "$t" || die "$t: a ${PIPE[$t]} package; this is a $PIPELINE build"
      set[$t]=1
    else
      die "unknown stage or package: $t"
    fi
  done
  mapfile -t TARGETS < <(printf '%s\n' "${!set[@]}" | sed '/^$/d' | sort)
  TPROV=()
  for t in "${TARGETS[@]}"; do
    for p in $(self_provides "$(build_of "$t")"); do
      TPROV[$p]=1
    done
  done
}

# Print the names of all stages: the trees with a stage file.
all_stages() {
  local d
  for d in "$base"/pos/*/; do
    [[ -f $d/stage ]] && basename "$d"
  done
  return 0
}

# What a build of the pipeline builds by default: every stage, or every
# toolchain package.
# Inputs:
#   PIPELINE    active pipeline name
pipeline_targets() {
  local p
  if [[ $PIPELINE == pos ]]; then
    all_stages
    return 0
  fi
  for p in "${PKGS[@]}"; do
    [[ ${KIND[$p]} == package ]] && in_pipeline "$p" && echo "$p"
  done
  return 0
}

# Warn about run-time requirements that nothing in the target set, or the
# toolchain a pos build takes from its reference, provides: the released
# archives would not be complete.
# Inputs:
#   $@    target package names
targets_check() {
  local p cap q found
  for p in "$@"; do
    for cap in ${REQ[$p]}; do
      found=
      for q in "$@"; do
        [[ " ${PROV[$q]} " == *" $cap "* ]] && { found=1; break; }
      done
      for q in ${PROVIDERS[$cap]:-}; do
        [[ ${PIPE[$q]} == toolchain ]] && found=1
      done
      [[ -n $found ]] || echo "warning: $p requires $cap, which no target provides" >&2
    done
  done
  return 0
}

# Packages that must be built for the targets: the targets themselves and
# every provider of a capability that has no available provider yet.
# Sets WANTED (sorted).
# Inputs:
#   $@    target package names
# Outputs:
#   WANTED (sorted array of unbuilt packages required for $@)
wanted() {
  local -A want=()
  local p cap q o b self changed=1
  for p in "$@"; do
    available "$p" || want[$(build_of "$p")]=1
  done
  while ((changed)); do
    changed=0
    for p in "${!want[@]}"; do
      self=" $(self_provides "$p" | xargs) "
      local -a caps=(${BREQ[$p]} ${REQ[$p]})
      for o in ${OUTS[$p]}; do
        caps+=(${REQ[$o]})
      done
      while ((${#caps[@]})); do
        cap=${caps[0]}
        caps=("${caps[@]:1}")
        [[ $self == *" $cap "* ]] && continue
        if provider "$cap"; then
          # A profile or host package is not built, so what it requires
          # is needed by the package that requires it.
          [[ ${KIND[$PROVIDER]:-} == host || ${KIND[$PROVIDER]:-} == profile ]] && caps+=(${REQ[$PROVIDER]})
          continue
        fi
        for q in ${PROVIDERS[$cap]:-}; do
          b=$(build_of "$q")
          # Only packages are built, each by the builds of its pipeline.
          [[ ${KIND[$b]} == package ]] || continue
          in_pipeline "$b" || continue
          if [[ -z ${want[$b]:-} ]] && ! available "$q"; then
            want[$b]=1
            changed=1
          fi
        done
      done
    done
  done
  mapfile -t WANTED < <(printf '%s\n' "${!want[@]}" | sed '/^$/d' | sort)
}

# Set NEXT to the next package to build: a wanted package whose environment
# resolves. A candidate obsoleted by another buildable candidate waits, so
# the replacement is built instead of the bootstrap package. A candidate
# whose environment takes a reference's copy of a package the run builds
# waits while another is ready: binutils is built with the build's
# linux-headers, not the reference's (it is built with the reference's
# gcc, which needs binutils). Returns 1 when nothing can be built.
# Inputs:
#   $@    target package names
# Outputs:
#   NEXT (package name ready to build), WANTED (array of remaining unbuilt packages)
next_package() {
  local p e
  local -a ready=() first=()
  local -A want=()
  wanted "$@"
  for p in "${WANTED[@]}"; do
    want[$p]=1
  done
  for p in "${WANTED[@]}"; do
    env_of "$p" || continue
    ready+=("$p")
    for e in "${ENV[@]}"; do
      is_ref "$e" && [[ -n ${want[$(build_of "${e%@*}")]:-} ]] && continue 2
    done
    first+=("$p")
  done
  for p in "${first[@]}" "${ready[@]}"; do
    if ! obsoleted_by_any "$p" "${ready[@]}"; then
      NEXT=$p
      return 0
    fi
  done
  return 1
}
