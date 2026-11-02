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
#   replaces-host-rpm  Fedora packages of host-requires and
#                   prepare-requires that this package stands for as a
#                   build tool: with an extras reference's tools, the
#                   tools image leaves out those of the tools' packages
#                   that the build-tools profile brings (container.sh)
#   provides        extra capabilities; every package provides its own name
#   obsoletes       packages this one replaces. Where both are available,
#                   the obsoleting package is the one chosen
#   source          source tree (default: the package name); its prepare
#                   recipe is prepare.sh of the package named after it
#   with-sources    further source trees the build copies into its own,
#                   each as a directory named after the source (gcc builds
#                   gmp, mpfr and mpc in its tree)
#   archive         <url> <sha256>: the package's source is this release
#                   archive, not a synced tree in src/. Patches in the
#                   package directory's patches/ (*.patch, applied with -p1
#                   in name order) are applied to it. Only in the package
#                   directory named after the source, without prepare.sh:
#                   a release archive is what prepare makes of a tree
#
# A source is the package's own tree's or common's; a source of another
# tree is named <tree>/<source>, so what crosses trees shows in the
# meta.
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
#                   source: nothing to build; holds the prepare recipe or
#                   the archive of a source other packages build from
#                   (with-sources)
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
# A build is in one of three pipelines (PIPELINE), and builds only the
# packages of its own. A toolchain build builds the toolchain packages; a
# pos build builds the OS; an extras build builds the extras (pos-extras),
# on both. Each takes what another builds from a reference (reference.sh):
# the toolchain from a toolchain reference (REF: its packages), glibc and
# the rest of core-libs and base from a pos reference (POSREF). A host or profile package is not available where a toolchain
# reference package obsoletes it, or a target of the run that does not
# itself require it: gcc-host, Fedora's compiler, stands in for gcc only
# in a build without a toolchain reference, and in the toolchain build
# that builds gcc with it.
#
# A project has the packages of one pipeline, which its project file names
# (pipeline; pos without one), and its builds are of that one (pos-sdk has
# the toolchain, pos-extras the extras, pos the rest): the others' are
# known from its references,
# by the meta each package installs (lib/pos/packages/<package>/meta), of
# the pipeline the reference's info names, and taken from it as below.
# They are FOREIGN; a capability nothing in the project provides is checked when a
# build resolves it.
#
# Where nothing available provides a capability, a build falls back to a
# reference's copy of a package: a toolchain package if the capability is
# a stand-in one (provided by a package another obsoletes: the
# reference's gcc stands in for gcc-host) or, in a pos or extras build, if
# no target of the run provides it (it is not being built); a pos package
# in a toolchain or extras build, or in a pos build if no target of the
# run provides it.
# In ENV it is <name>@ref (toolchain reference) or <name>@pos (pos
# reference). Its own requirements are those it was built with (REF_REQ),
# and are met by this build's packages where they are built, otherwise by
# the references', whether or not they are targets: the reference's gcc
# builds glibc, which gcc itself requires.
# A requirement of a toolchain reference package that this build installs
# in another prefix is met by the reference's: its gcc runs its own as and
# ld, by the paths it was built with.
#
# Every package build gets the build tools (BUILD.md "Build tools"). With
# the tools setting fedora (TOOLS_REF none) they are host-base, a
# requirement like any other. With an extras reference they are what the
# build-tools profile requires, resolved after the package's own
# environment: a tool the environment already provides is not added, and
# one it does not is the tools reference's (<name>@tools, in its own
# prefix) or the pos reference's (<name>@pos), never this build's, so a
# tool never makes a build wait, also not one of a package the run builds
# (bash in a pos build). The requirements of a tools package that the
# tools reference provides are its own, in its prefix (its perl runs its
# autoconf); the rest, /pos packages, are the environment's where it has
# them, so tools run on what the build built. Packages added only for the
# tools are TOOLENV; a package build may not link their libraries
# (pkg.sh: _pkg_linkcheck).

declare -a PKGS=()
declare -A KIND=() REQ=() BREQ=() HREQ=() PREQ=() PROV=() OBS=() SRC=() WSRC=() OUTS=() PARENT=()
declare -A PIPE=() PKGDIR=() SRCPATH=() SRCREFS=() ARCHIVE=() VERSION=() PFX=()
declare -A PROVIDERS=() BOOTCAP=() TPROV=()
declare -A BUILT=() REF=() POSREF=() REF_REQ=() FOREIGN=()
declare -A TOOLSREF=() TOOLS_REQ=() TOOLS_HREPL=() TOOLENV=()
# Memos of what does not change within a run (resolution asks them for
# every capability of every package, again for each package it picks):
# whether a host or profile package is available (TARGETS and REF; reset
# by targets_expand and load_references), and the capabilities of a
# package's build. TOOLSMEMO: the build tools env_tools adds, by what of
# their closure (TOOLSKEY) the environment already has (reset by
# load_references).
declare -A HOSTAVAIL=() SELFPROV=() TOOLSMEMO=() TOOLSMISS=()
declare -a TOOLSKEY=()
# next_package's environments (next_built).
declare -A NEXTENV=() NEXTREV=() NEXTBUILT=() PROVMEMO=()
declare -a TARGETS=()
PIPELINE=pos
# The prefix the build's packages install in (build.sh: project_prefix).
PREFIX=/pos

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
    [[ -e $f ]] || continue
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
#   SRCREFS (source and with-sources as written), SRCPATH, ARCHIVE, VERSION, OUTS,
#   PARENT, PIPE, PROVIDERS, BOOTCAP
#   PIPELINE    the project's pipeline, from its project file
meta_load() {
  local dir p key vals line r
  PIPELINE=$(awk '$1 == "pipeline" {print $2}' "$base/project" 2>/dev/null) || true
  PIPELINE=${PIPELINE:-pos}
  case $PIPELINE in
    pos|toolchain|extras) ;;
    *) die "$base/project: unknown pipeline: $PIPELINE" ;;
  esac
  sources_load
  for dir in "$base"/pos/*/packages/*/; do
    dir=${dir%/}
    p=${dir##*/}
    [[ -z ${PKGDIR[$p]:-} ]] || die "package $p is in two trees: ${PKGDIR[$p]} and ${dir#"$base"/}"
    PKGDIR[$p]=${dir#"$base"/}
    [[ -f $dir/meta ]] || die "${PKGDIR[$p]}: missing meta"
    PKGS+=("$p")
    KIND[$p]=package REQ[$p]= BREQ[$p]= HREQ[$p]= PREQ[$p]= PROV[$p]=$p OBS[$p]= SRC[$p]=$p
    WSRC[$p]= OUTS[$p]= PARENT[$p]= PIPE[$p]=$PIPELINE
    while read -r line; do
      line=${line%%#*}
      read -r key vals <<<"$line"
      [[ -z $key ]] && continue
      case $key in
        requires) REQ[$p]+=" $vals" ;;
        build-requires) BREQ[$p]+=" $vals" ;;
        host-requires) HREQ[$p]+=" $vals" ;;
        prepare-requires) PREQ[$p]+=" $vals" ;;
        replaces-host-rpm) ;; # read from the tools reference (load_references)
        provides) PROV[$p]+=" $vals" ;;
        obsoletes) OBS[$p]+=" $vals" ;;
        source) SRC[$p]=$vals ;;
        with-sources) WSRC[$p]+=" $vals" ;;
        archive) ARCHIVE[$p]=$vals ;;
        version) VERSION[$p]=$vals ;;
        prefix) PFX[$p]=$vals ;;
        kind) KIND[$p]=$vals ;;
        outputs) OUTS[$p]+=" $vals" ;;
        output-of) PARENT[$p]=$vals ;;
        pipeline) die "${PKGDIR[$p]}/meta: pipeline is the project's, in its project file" ;;
        *) die "${PKGDIR[$p]}/meta: unknown key: $key" ;;
      esac
    done <"$dir/meta"
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
  meta_index
}

# Sort PKGS and index them: PROVIDERS and BOOTCAP (the capabilities of
# obsoleted packages).
# Inputs:
#   PKGS, PROV, OBS
# Outputs:
#   PKGS (sorted), PROVIDERS, BOOTCAP
meta_index() {
  local p cap q
  mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | sort)
  PROVIDERS=() BOOTCAP=()
  for p in "${PKGS[@]}"; do
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

# Add the packages of a restored reference the checkout has no recipe for
# (FOREIGN, see the top), from the meta each installed: what the resolver
# needs of a package it takes from a reference. Their pipeline is the
# reference's (pos for builds from before pipelines); a pipeline line in
# a meta, from before the project named it, is not read.
# Inputs:
#   $1      reference ID, or none
#   refs    work/references directory
# Outputs:
#   PKGS, KIND, PIPE, REQ, PROV, OBS, OUTS, PARENT, PFX, FOREIGN; meta_index
foreign_load() {
  local meta p key vals line pipe
  [[ $1 != none ]] || return 0
  pipe=$(ref_info "$1" pipeline)
  while read -r meta; do
    p=$(basename "$(dirname "$meta")")
    [[ -z ${KIND[$p]:-} || -n ${FOREIGN[$p]:-} ]] || continue
    FOREIGN[$p]=1
    PKGS+=("$p")
    KIND[$p]=package REQ[$p]='' BREQ[$p]='' HREQ[$p]='' PREQ[$p]='' PROV[$p]=$p OBS[$p]='' SRC[$p]=$p
    WSRC[$p]='' OUTS[$p]='' PARENT[$p]='' PIPE[$p]=${pipe:-pos}
    while read -r line; do
      line=${line%%#*}
      read -r key vals <<<"$line"
      case $key in
        requires) REQ[$p]+=" $vals" ;;
        provides) PROV[$p]+=" $vals" ;;
        obsoletes) OBS[$p]+=" $vals" ;;
        kind) KIND[$p]=$vals ;;
        outputs) OUTS[$p]+=" $vals" ;;
        output-of) PARENT[$p]=$vals ;;
        prefix) PFX[$p]=$vals ;;
      esac
    done <"$meta"
  done < <(ref_metas "$1")
  mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | sort -u)
  meta_index
}

# Validate all loaded package metadata for missing recipes, broken output-of
# links, missing capability providers, and incomplete obsoletes coverage.
# Inputs:
#   base, PKGS, PKGDIR, KIND, PARENT, OUTS, REQ, BREQ, PROVIDERS, WSRC,
#   SRCREFS, SRCPATH, ARCHIVE, VERSION, OBS, PROV
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
    done
    # A package of another project's prefix can install in pos's: pos-sdk's
    # gcc-runtime, which pos ships (BUILD.md "Prefix").
    if [[ -n ${PFX[$p]:-} && ${PFX[$p]} != /pos ]]; then
      echo "$m: prefix: only /pos, pos's prefix, where the project's is another" >&2
      err=1
    fi
    if [[ -n ${ARCHIVE[$p]:-} && -z ${VERSION[$p]:-} || -z ${ARCHIVE[$p]:-} && -n ${VERSION[$p]:-} ]]; then
      echo "$m: archive and version go together: the release and its version" >&2
      err=1
    elif [[ -n ${VERSION[$p]:-} && ! ${VERSION[$p]} =~ ^[0-9A-Za-z._+~-]+$ ]]; then
      echo "$m: version: one word of letters, digits and . _ + ~ -" >&2
      err=1
    fi
    if [[ -n ${ARCHIVE[$p]:-} ]]; then
      if [[ ! ${ARCHIVE[$p]} =~ ^[a-z]+://[^[:space:]]+/[^/[:space:]]+[[:space:]]+[0-9a-f]{64}$ ]]; then
        echo "$m: archive: expected <url> <sha256>" >&2
        err=1
      fi
      if [[ ${KIND[$p]} != package && ${KIND[$p]} != source || ${SRC[$p]} != "$p" ]]; then
        echo "$m: archive is for the package directory of its own source" >&2
        err=1
      fi
      if [[ -e $base/${SRCPATH[$p]} || -f $base/${PKGDIR[$p]}/prepare.sh ]]; then
        echo "$m: archive, and also ${SRCPATH[$p]} or prepare.sh" >&2
        err=1
      fi
    fi
    for q in ${WSRC[$p]}; do
      if [[ -z ${ARCHIVE[$q]:-} && ! -d $base/${SRCPATH[$q]} ]]; then
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
    host|profile)
      if [[ -z ${HOSTAVAIL[$1]:-} ]]; then
        HOSTAVAIL[$1]=no
        ! obsoleted_by_any "$1" "${!REF[@]}" && ! obsoleted_by_target "$1" && HOSTAVAIL[$1]=yes
      fi
      [[ ${HOSTAVAIL[$1]} == yes ]]
      ;;
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
    b=$t
    [[ ${KIND[$t]} != output ]] || b=${PARENT[$t]}
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

# Set SELF to the capabilities a build provides (self_provides), as
# " <cap> ... ", for matching " $cap ".
# Inputs:
#   $1    package name
# Outputs:
#   SELF (shell variable)
self_caps() {
  local o
  if [[ -z ${SELFPROV[$1]:-} ]]; then
    SELFPROV[$1]=" ${PROV[$1]} "
    for o in ${OUTS[$1]}; do
      SELFPROV[$1]+="${PROV[$o]} "
    done
  fi
  SELF=${SELFPROV[$1]}
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
  local key="$1 ${2:-}"
  [[ -z ${ENVDEPS_ON:-} ]] || ENVDEPS[$1]=1
  [[ -n ${PROVMEMO_ON:-} ]] || { provider_find "$@"; return; }
  if [[ -z ${PROVMEMO[$key]+set} ]]; then
    PROVMEMO[$key]=
    provider_find "$@" && PROVMEMO[$key]=$PROVIDER
  fi
  PROVIDER=${PROVMEMO[$key]}
  [[ -n $PROVIDER ]]
}

# provider, which within next_package keeps its answers (PROVMEMO, by
# capability and ref) until a provider of the capability is built
# (next_built).
provider_find() {
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
    1)
      PROVIDER=${chosen[0]}
      # The reference's compiler runs the tools at the paths it was built
      # with (gcc's --with-as): where this build installs them in another
      # prefix (a new sdk version), it gets the reference's.
      p=$PROVIDER
      if [[ -n $ref && -n ${REF[$p]:-} && $(pkg_prefix "$p") != "$(env_prefix "$p@ref")" ]]; then
        PROVIDER=$p@ref
      fi
      ;;
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
        [[ $PIPELINE != toolchain && -z ${TPROV[$cap]:-} ]] || continue
      PROVIDER=$p@ref
      return 0
    elif [[ -n ${POSREF[$p]:-} ]]; then
      [[ -n $ref || $PIPELINE != pos || -z ${TPROV[$cap]:-} ]] || continue
      PROVIDER=$p@pos
      return 0
    elif [[ -n ${TOOLSREF[$p]:-} && $PIPELINE != extras ]]; then
      PROVIDER=$p@tools
      return 0
    fi
  done
  return 1
}

# The tools' copy of a provider (see the top): the tools reference's
# (<name>@tools), else the toolchain reference's (<name>@ref: gcc-runtime
# of the C++ tools) or the pos reference's (<name>@pos).
# Inputs:
#   $1    capability name
# Outputs:
#   PROVIDER (shell variable)
provider_tools() {
  local p
  for p in ${PROVIDERS[$1]:-}; do
    [[ -z ${TOOLSREF[$p]:-} ]] || { PROVIDER=$p@tools; return 0; }
  done
  for p in ${PROVIDERS[$1]:-}; do
    [[ -z ${REF[$p]:-} ]] || { PROVIDER=$p@ref; return 0; }
    [[ -z ${POSREF[$p]:-} ]] || { PROVIDER=$p@pos; return 0; }
  done
  return 1
}

# Return 0 if an environment entry is satisfied from a reference build
# (<pkg>@ref, <pkg>@pos or <pkg>@tools).
# Inputs:
#   $1    environment entry
is_ref() {
  [[ $1 == *@ref || $1 == *@pos || $1 == *@tools ]]
}

# Resolve the build environment of a package: its requirements and,
# recursively, the run-time requirements of each provider chosen. A
# requirement the build itself provides (gcc requires its own output
# gcc-runtime) is installed with the package, not needed to build it.
# Reached through another package's requirements, it is needed (systemd
# links util-linux's libmount, which links libsystemd), and the reference's
# copy is used, as in a new build, where the package is not built yet. Then
# the build tools (see the top). Sets ENV (sorted package names), TOOLENV
# (the entries only the tools brought) and MISSING (capabilities with no
# available provider). Returns 1 when anything is missing.
# Inputs:
#   $1    package name, or nothing for the tools alone (prepare)
#   TOOLS_REF
#   ENV_UNSORTED  set: ENV unsorted (next_package, which only looks)
# Outputs:
#   ENV (array of resolved package names), TOOLENV, MISSING (array of
#   unresolved capabilities)
env_of() {
  local p=${1:-} cap entry ref q
  local -a queue=()
  local -A seen=() inenv=()
  local self=' '
  ENV=() MISSING=() TOOLENV=()
  if [[ -n $p ]]; then
    self_caps "$p"
    self=$SELF
    for cap in ${BREQ[$p]} ${REQ[$p]}; do
      [[ $self == *" $cap "* ]] || queue+=("$cap")
    done
    [[ $TOOLS_REF != none || ${KIND[$p]} != package ]] || queue+=(host-base)
  fi
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
  [[ $TOOLS_REF == none ]] || env_tools inenv
  if [[ -n ${ENV_UNSORTED:-} ]]; then
    ENV=("${!inenv[@]}")
  else
    mapfile -t ENV < <(printf '%s\n' "${!inenv[@]}" | sort)
  fi
  ((${#MISSING[@]} == 0))
}

# Add the build tools to an environment (env_of): the build-tools
# profile, with what it requires and what that requires, as the top says.
# An entry is tool:<capability>, or own:<capability> for a requirement of
# a tools package, which its own reference meets. A capability the
# environment provides is not looked for, and an entry already in it not
# followed, so what is added depends only on which of the closure's
# capabilities and providers (TOOLSKEY, env_tools_walk with no
# environment) the environment has: memoized by that.
# Inputs:
#   $1        name of the environment map (env_of: inenv)
#   TOOLSREF, TOOLS_REQ, REF, POSREF, REF_REQ
# Outputs:
#   the map, TOOLENV, MISSING
env_tools() {
  local -n env=$1
  local e q key=
  local -A has=()
  if ((${#TOOLSKEY[@]} == 0)); then
    local -A none=() once=()
    env_tools_walk none
    for e in "${TOOLSKEY[@]}"; do
      [[ -n ${once[$e]:-} ]] || once[$e]=1
    done
    TOOLSKEY=("${!once[@]}")
  fi
  for e in "${!env[@]}"; do
    for q in ${PROV[${e%@*}]}; do has[$q]=1; done
  done
  for e in "${TOOLSKEY[@]}"; do
    if [[ $e == cap:* ]]; then
      key+=${has[${e#cap:}]:+1}.
    else
      key+=${env[$e]:+1}.
    fi
  done
  if [[ -z ${TOOLSMEMO[$key]+set} ]]; then
    local -a added=() missing=("${MISSING[@]}")
    MISSING=()
    env_tools_walk env has
    TOOLSMEMO[$key]="${added[*]}"
    TOOLSMISS[$key]="${MISSING[*]}"
    MISSING=("${missing[@]}")
  fi
  for e in ${TOOLSMEMO[$key]}; do
    env[$e]=1
    TOOLENV[$e]=1
  done
  MISSING+=(${TOOLSMISS[$key]})
}

# The walk of env_tools. Without an environment (has not given), it
# follows every entry and records in TOOLSKEY each capability it would
# look for (cap:<capability>) and each provider it would add.
# Inputs:
#   $1        name of the environment map
#   $2        name of the map of the capabilities it provides, if any
# Outputs:
#   the map, added (array, of the caller), MISSING; TOOLSKEY
env_tools_walk() {
  local -n wenv=$1
  local entry cap q i=0 all=1
  local -a queue=(tool:build-tools)
  local -A seen=() nohas=()
  if [[ -n ${2:-} ]]; then
    local -n whas=$2
    all=
  else
    local -n whas=nohas
  fi
  while ((i < ${#queue[@]})); do
    entry=${queue[i++]}
    [[ -z ${seen[$entry]:-} ]] || continue
    seen[$entry]=1
    cap=${entry#*:}
    PROVIDER=
    if [[ $cap == build-tools ]]; then
      [[ ${KIND[build-tools]:-} == profile ]] ||
        die "tools $TOOLS_REF: the project has no build-tools profile (pos/build-env/packages/build-tools)"
      PROVIDER=build-tools
    elif [[ $entry == own:* ]]; then
      for q in ${PROVIDERS[$cap]:-}; do
        [[ -z ${TOOLSREF[$q]:-} ]] || { PROVIDER=$q@tools; break; }
      done
    fi
    if [[ -z $PROVIDER ]]; then
      [[ -z $all ]] || TOOLSKEY+=("cap:$cap")
      [[ -z ${whas[$cap]:-} ]] || continue
      provider_tools "$cap" || { [[ -n $all ]] || MISSING+=("$cap"); continue; }
    fi
    [[ -z $all ]] || TOOLSKEY+=("$PROVIDER")
    [[ -z ${wenv[$PROVIDER]:-} ]] || continue
    wenv[$PROVIDER]=1
    if [[ -z $all ]]; then
      added+=("$PROVIDER")
      for q in ${PROV[${PROVIDER%@*}]}; do whas[$q]=1; done
    fi
    case $PROVIDER in
      *@tools) for q in ${TOOLS_REQ[${PROVIDER%@*}]:-}; do queue+=("own:$q"); done ;;
      *@ref|*@pos) for q in ${REF_REQ[${PROVIDER%@*}]:-}; do queue+=("tool:$q"); done ;;
      *) for q in ${REQ[$PROVIDER]}; do queue+=("tool:$q"); done ;;
    esac
  done
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

# The entries of the environment that set up the build (buildsys/pkg.sh)
# with an env.sh: a reference's package with the one it installed
# (lib/pos/packages/<package>/env.sh), else the recipe's.
# Inputs:
#   ENV    resolved environment array from env_of
env_scripts() {
  local q
  for q in "${ENV[@]}"; do
    env_script "$q" >/dev/null && echo "$q"
  done
  return 0
}

# The env.sh of an environment entry (env_scripts) in the build container,
# where the reference's package is in its prefix (env_prefix) and the
# recipes at their host path. Returns 1 when it has none.
# Inputs:
#   $1      environment entry
#   [$2]    host path of base (default base)
env_script() {
  local q=$1 p=${1%@*} pre
  env_prefix_v "$q"
  pre=$ENVPFX
  if is_ref "$q" && env_tree_v "$q" && [[ -f $ENVTREE$pre/lib/pos/packages/$p/env.sh ]]; then
    echo "$pre/lib/pos/packages/$p/env.sh"
  elif [[ -n ${PKGDIR[$p]:-} && -f $base/${PKGDIR[$p]}/env.sh ]]; then
    echo "${2:-$base}/${PKGDIR[$p]}/env.sh"
  else
    return 1
  fi
}

# Expand target names (stages or packages) into TARGETS (package names),
# and TPROV, the capabilities their builds provide. A pos build leaves out
# the toolchain packages of a stage, which its reference has; a toolchain
# or extras build has packages of its pipeline only, and no stages.
# Inputs:
#   $@    stage names and/or package names
# Outputs:
#   TARGETS (sorted array of package names), TPROV (map of capabilities provided by TARGETS)
targets_expand() {
  local t p
  local -A set=()
  for t in "$@"; do
    if [[ -f $(stage_file "$t") ]]; then
      [[ $PIPELINE == pos ]] || die "$t: a $PIPELINE build builds its packages, not stages"
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
  TPROV=() HOSTAVAIL=()
  next_reset
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

# What a build of the pipeline builds by default: every stage (pos), or
# every package and output of the pipeline (toolchain, extras), as a stage
# lists outputs.
# Inputs:
#   PIPELINE    active pipeline name
pipeline_targets() {
  local p
  if [[ $PIPELINE == pos ]]; then
    all_stages
    return 0
  fi
  for p in "${PKGS[@]}"; do
    [[ ${KIND[$p]} == package || ${KIND[$p]} == output ]] && in_pipeline "$p" && echo "$p"
  done
  return 0
}

# Warn about run-time requirements that nothing in the target set, or a
# package of another pipeline (taken from a reference, released by its own
# project), provides: the released archives would not be complete.
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
        [[ ${PIPE[$q]} != "$PIPELINE" ]] && found=1
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
    q=$p
    [[ ${KIND[$p]} != output ]] || q=${PARENT[$p]}
    available "$p" || want[$q]=1
  done
  while ((changed)); do
    changed=0
    for p in "${!want[@]}"; do
      self_caps "$p"
      self=$SELF
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
          b=$q
          [[ ${KIND[$q]} != output ]] || b=${PARENT[$q]}
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
# waits while another is ready: a package built with the toolchain
# reference's gcc gets the build's glibc, which gcc requires, once it is
# built, not the pos reference's. Returns 1 when nothing can be built.
# What a candidate's environment comes to (NEXTENV: whether it resolves,
# and the packages it takes a reference's copy of) is kept from pick to
# pick: it changes only when a provider of a capability the resolution
# asked about (provider) is built, or a package is dropped (next_built).
# Inputs:
#   $@    target package names
# Outputs:
#   NEXT (package name ready to build), WANTED (array of remaining unbuilt packages)
next_package() {
  local p e q ENV_UNSORTED=1 ENVDEPS_ON= PROVMEMO_ON=1
  local -a ready=() first=() rec=()
  local -A want=() owners=() ENVDEPS=()
  wanted "$@"
  for p in "${WANTED[@]}"; do
    want[$p]=1
  done
  next_built
  for p in "${WANTED[@]}"; do
    if [[ -z ${NEXTENV[$p]+set} ]]; then
      ENVDEPS=() ENVDEPS_ON=1
      if env_of "$p"; then
        owners=()
        for e in "${ENV[@]}"; do
          [[ -z ${TOOLENV[$e]:-} ]] || continue
          is_ref "$e" || continue
          q=${e%@*}
          [[ ${KIND[$q]} != output ]] || q=${PARENT[$q]}
          owners[$q]=1
        done
        NEXTENV[$p]="ok ${!owners[*]}"
      else
        NEXTENV[$p]=missing
      fi
      for q in "${!ENVDEPS[@]}"; do
        NEXTREV[$q]+=" $p"
      done
      ENVDEPS_ON=
    fi
    rec=(${NEXTENV[$p]})
    [[ ${rec[0]} == ok ]] || continue
    ready+=("$p")
    for q in "${rec[@]:1}"; do
      [[ -z ${want[$q]:-} ]] || continue 2
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

# Forget what next_package keeps that a change of BUILT since the last
# pick touches: for each capability of a package built since, the
# provider answers (PROVMEMO) and the environments of the packages whose
# resolution asked about it (NEXTREV); all of it when one was dropped.
# Inputs:
#   BUILT, NEXTBUILT (BUILT as of the last pick), NEXTREV
# Outputs:
#   NEXTENV, NEXTBUILT, NEXTREV, PROVMEMO
next_built() {
  local b p cap
  for b in "${!BUILT[@]}"; do
    [[ -z ${NEXTBUILT[$b]:-} ]] || continue
    NEXTBUILT[$b]=1
    for cap in ${PROV[$b]:-}; do
      unset "PROVMEMO[$cap ]" "PROVMEMO[$cap 1]"
      for p in ${NEXTREV[$cap]:-}; do
        unset "NEXTENV[$p]"
      done
    done
  done
  if ((${#NEXTBUILT[@]} != ${#BUILT[@]})); then
    next_reset
    for b in "${!BUILT[@]}"; do
      NEXTBUILT[$b]=1
    done
  fi
}

# Forget all next_package keeps, when what resolution reads besides BUILT
# changes (load_references, targets_expand).
next_reset() {
  NEXTENV=() NEXTREV=() NEXTBUILT=() PROVMEMO=()
}
