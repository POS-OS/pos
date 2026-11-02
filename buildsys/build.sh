#!/usr/bin/env bash
# Build POS. Resolves package dependencies, runs each package build in a
# container of its own and assembles the stage archives. Runs on the host
# or in any toolbox; it needs podman.
#
# Every run belongs to a build, identified by a timestamp ID. A build keeps
# its outputs in work/builds/<id>. A package is built once per build; run
# continues the current build.
#
# A source with a prepare recipe (prepare.sh of the package named after the
# source) is prepared before it is built: the committed source
# (pos/<tree>/src/<source>, resolve.sh) is copied and turned into
# what a release tarball holds (buildsys/prepare.sh). Prepared trees are kept
# in work/sources/<source>/<key>, keyed by their inputs, and shared by
# builds. A source from a release archive (meta "archive") is downloaded
# into the download directory (setting download-dir), checked against its
# sha256, and unpacked with its patches into work/sources/<source>/<key>
# the same way. Downloads and prepares are the steps with network; package
# builds have none.
#
# Every step of a build (prepare, package build, output) runs in a
# container of the build's tools image: Fedora's container image with the
# Fedora packages every step declares, made when the build is created. A
# step sees that image and the paths it is given, nothing else of the host;
# only what an output does with the host's podman runs outside one
# (outputs.sh). A package build gets a /pos of exactly its resolved environment, composed
# for it and mounted read-only.
#
# A build is a toolchain build or a pos build (resolve.sh). The toolchain
# (gcc, binutils) is built by toolchain builds, with
# the toolchain of a toolchain reference, a stored toolchain build
# (work/references/<ref>, restored from the reference store), or Fedora's
# without one, on the glibc of a pos reference, a stored pos build
# (reference.sh). A pos build builds the rest with its toolchain
# reference's toolchain, and assembles the stages with the reference's
# toolchain packages in them. podman runs on the host; from inside a
# toolbox through flatpak-spawn.
#
# The engine, this buildsys/, builds a project: the checkout POS_PROJECT
# names, else the one the engine is in. Recipes, stages, outputs, VERSION
# and work/ are the project's; a build records the engine's commit when it
# is another checkout's (BUILD.md "Engine").

set -euo pipefail

engine=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
base=$(cd "${POS_PROJECT:-$engine}" && pwd -P)
# The scripts the engine runs (assemble.sh) build the same project.
export POS_PROJECT=$base
# shellcheck source=resolve.sh
source "$engine/buildsys/resolve.sh"
# shellcheck source=config.sh
source "$engine/buildsys/config.sh"
# shellcheck source=buildinfo.sh
source "$engine/buildsys/buildinfo.sh"

builds=$base/work/builds
# Package builds by build key (build_key), which run reuses: cache_store.
cache=$base/work/cache
CHECKS=yes
NO_CACHE=
# The stale packages of the build (stale_check) and why.
declare -A STALE=() CHECKED=()
# The Fedora packages of the tools image by host-requires (tools_versions).
declare -A FEDORA=()
# Who commits VERSION bumps, as the source syncs are committed.
bot_name=pos-bot bot_email=pos-bot@devzero.dk
sources=$base/work/sources
downloads=$(config download-dir)
downloads=${downloads:-$base/work/downloads}
refs=$base/work/references
# The recipes of the checkout, as git pathspecs: the package directories
# and the stage lists of every tree (resolve.sh).
RECIPES=(':(glob)pos/*/packages/**' ':(glob)pos/*/stage')
fedora_release=$(config fedora-release)
fedora_image=registry.fedoraproject.org/fedora
export LC_ALL=C

# shellcheck source=container.sh
source "$engine/buildsys/container.sh"
# shellcheck source=reference.sh
source "$engine/buildsys/reference.sh"
# shellcheck source=release.sh
source "$engine/buildsys/release.sh"
# shellcheck source=outputs.sh
source "$engine/buildsys/outputs.sh"


usage() {
  cat >&2 <<EOF
usage: ./build plan [--new] [<target>...]
                                               print what run would build, in order
       ./build run [--new [--source-archives]] [--no-checks] [--no-cache] [<target>...]
                                               build the targets, then assemble stage
                                               archives and make the outputs
       ./build prepare [<target>...]           download and prepare the sources of the
                                               targets now
       ./build rebuild <package>...            drop packages from the current build
       ./build output [--no-checks] [<output>...]
                                               make outputs of the current build again
       ./build status                          show the current build
       ./build reference [<id>]                store a toolchain or extras build, or
                                               a pos build's core-libs and base, as the
                                               default reference of its kind
       ./build clean [<id>]                    remove the tools image of a build
       ./build prune [-n]                      remove the builds but the current and newest
                                               keep-builds others, and what they alone
                                               needed: images, references, source trees,
                                               cache entries (-n: list them)
       ./build validate [--unchecked] [<id>]   check that a build is an OS build
       ./build tag [--unchecked]               number the current build: validate it,
                                               tag its commit main-<BUILD>, then bump
       ./build publish [--unchecked]           number the current build as tag does and
                                               copy its artifacts into the release library
       ./build bump                            commit VERSION with the next BUILD

A target is a stage (pos/<stage>/stage) or a package. The default is
every stage. run continues the current build; --new starts another, of
the project's pipeline: a toolchain build (pos-sdk) builds the toolchain
packages (project: pipeline toolchain) and what they need; an extras
build (pos-extras, pipeline extras) builds the extras packages; a pos build
builds the rest, and takes the toolchain from its toolchain reference. An output
(outputs/<output>: images, disks, RPM packages) is made when run
assembles all the stages it requires, after the outputs it requires.
--source-archives makes the new build also write an archive of every
source it built from (pos-src-<source>-<key>.tar.zst, or the release
archive as downloaded, pos-src-<archive>) and of the build recipes
(<project>-recipes-<stem>.tar.zst, pos-recipes for pos).
A package whose build key (its inputs) matches one built before is taken
from the build cache (work/cache); --no-cache compiles every package the
run builds.

A new build takes the toolchain from a toolchain reference, a stored
toolchain build, and core-libs and base from a pos reference, a stored
pos build's core-libs and base stages; by default the ones reference marked last.
A toolchain build takes the pos reference its project file pins
(pos-reference), the oldest glibc its toolchain runs on. A toolchain build
without a toolchain reference (none) is built by Fedora's compiler; it needs a pos
reference. A pos build without one builds glibc, the first pos reference.
An extras build needs both references.
It builds the checkout POS_PROJECT names, else the one of this buildsys.
Settings (build.conf.dist) are read from
$build_config and $project_config; an environment variable overrides one:
  fedora-release  POS_FEDORA_RELEASE  the Fedora release (default 44)
  tools-image     POS_TOOLS_IMAGE     the image tools are installed on
                                      (default $fedora_image:<release>)
  reference-dir   POS_REFERENCE_DIR   the reference store
  toolchain-reference  POS_TOOLCHAIN_REFERENCE  the toolchain reference, or none
  pos-reference   POS_POS_REFERENCE   the pos reference, or none
  tools           POS_TOOLS           the build tools: an extras reference
                                      (default: the store's), or fedora
  release-dir     POS_RELEASE_DIR     the release library publish copies into
  download-dir    POS_DOWNLOAD_DIR    the sources' release archives
                                      (default work/downloads)
  engine-checkout POS_ENGINE_CHECKOUT the pos checkout another project's
                                      ./build takes the engine from
  keep-builds     POS_KEEP_BUILDS     builds prune keeps besides the current
                                      one, the newest (default 2)
EOF
  exit 1
}



# The run's progress in the terminal title, for whoever watches it. It is
# written to the terminal, so it stays out of the output and the logs. Under
# tmux it is the pane title, which the default status line shows. The title
# from before the run is put back when it ends.
TITLE=
TITLE_SAVED=

title_init() {
  [[ -t 2 ]] && { : >/dev/tty; } 2>/dev/null || return 0
  TITLE=1
  if [[ -n ${TMUX:-} ]] && command -v tmux >/dev/null; then
    TITLE_SAVED=$(tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_title}' 2>/dev/null) || true
  else
    printf '\e[22;0t' >/dev/tty
  fi
  trap title_restore EXIT
}

title() {
  [[ -n $TITLE ]] || return 0
  printf '\e]2;%s %s\a' "$project" "$*" >/dev/tty 2>/dev/null || true
}

title_restore() {
  if [[ -n ${TMUX:-} ]] && command -v tmux >/dev/null; then
    tmux select-pane -t "${TMUX_PANE:-}" -T "$TITLE_SAVED" 2>/dev/null || true
  else
    printf '\e[23;0t' >/dev/tty 2>/dev/null || true
  fi
}

# Print the current build ID from the $builds/current symlink, or return 1.
current_id() {
  [[ -L $builds/current ]] && basename "$(readlink "$builds/current")"
}

# A pos build without a toolchain reference is the bootstrap of the first
# pos reference: it builds packages (glibc) with Fedora's compiler, not
# stages, which hold the toolchain.
# Inputs:
#   $@              targets as given (stages and/or packages)
#   PIPELINE, TOOLCHAIN_REF
bootstrap_check() {
  local t
  [[ $PIPELINE == pos && $TOOLCHAIN_REF == none ]] || return 0
  for t in "$@"; do
    [[ ! -f $(stage_file "$t") ]] ||
      die "$t: a pos build without a toolchain reference builds packages, not stages (BUILD.md \"Toolchain\")"
  done
}

# Create a new build directory under $builds/<id>, build its tools container
# image, write $builds/<id>/info, and point $builds/current at it. Called
# in the shell itself, not in a command substitution, where errexit would
# not stop it at a failed step.
# Inputs:
#   $1          whether to produce source archives ("yes" or "no")
#   PIPELINE    active pipeline name (pos, toolchain or extras)
# Outputs:
#   id, bdir    the new build's ID and directory
#   PREFIX      the prefix its packages install in (project_prefix)
build_new() {
  local archives=$1 from branch version
  id=$(date +%Y%m%d%H%M)
  [[ ! -e $builds/$id ]] || die "build $id already exists; wait a minute"
  branch=$(git -C "$base" rev-parse --abbrev-ref HEAD)
  version=$(version_info HEAD "$branch" "$id") || exit 1
  PREFIX=$(project_prefix "$version")
  references_choose
  load_references
  from=$(tools_base)
  bdir=$builds/$id
  mkdir -p "$bdir"/{dest,debug,build,logs}
  tools_build "$from"
  {
    echo "id $id"
    echo "pipeline $PIPELINE"
    echo "prefix $PREFIX"
    echo "fedora $fedora_release"
    echo "tools-base $from"
    echo "tools-image $(tools_image)"
    echo "toolchain-reference $TOOLCHAIN_REF"
    echo "pos-reference $POS_REF"
    echo "tools-reference $TOOLS_REF"
    echo "branch $branch"
    tree_state | awk '{print "commit", $1; print "tree", $2} NF > 2 {print "engine", $4}'
    echo "$version"
    echo "started $(date -u +%FT%TZ)"
    echo "source-archives $archives"
  } >"$builds/$id/info"
  ln -sfn "$id" "$builds/current"
}

# The prefix the project's packages install in: the project file's prefix
# line (default /pos), its <version> the build's <product
# version>.<revision>, which stays the same while developing and changes
# with a service release, and its <release> the build's product release,
# <branch>.<timestamp> while developing (BUILD.md "Prefix").
# Inputs:
#   $1      the build's version lines (version_info)
#   base    the project checkout
project_prefix() {
  local p v r
  p=$(awk '$1 == "prefix" {print $2}' "$base/project")
  p=${p:-/pos}
  [[ $p == /?* && $p != */ ]] || die "$base/project: prefix is an absolute path, not '$p'"
  v=$(awk '$1 == "product-version" {pv = $2} $1 == "revision" {r = $2} END {print pv "." r}' <<<"$1")
  r=$(awk '$1 == "product-release" {print $2}' <<<"$1")
  p=${p//<version>/$v}
  echo "${p//<release>/$r}"
}

# The sdk's prefix in a project of prefix $1: /pos/sdk in pos's prefix
# (toolchains from before prefixes), else the whole prefix
# (/apps/pos-sdk/<version>).
# Inputs:
#   $1      a toolchain build's prefix
sdk_of() {
  if [[ $1 == /pos ]]; then echo /pos/sdk; else echo "$1"; fi
}

# The sdk prefix of the build's compiler, its toolchain reference's, also
# in a toolchain build, which installs the new one in its own prefix
# (/pos/sdk without one: Fedora's compiler does not use it).
# Inputs:
#   TOOLCHAIN_REF
sdk_prefix() {
  if [[ $TOOLCHAIN_REF != none ]]; then
    sdk_of "$(ref_prefix "$TOOLCHAIN_REF")"
  else
    echo /pos/sdk
  fi
}

# The prefix a package of this build installs in: the build's, or /pos for
# one whose meta says so (PFX).
# Inputs:
#   $1      package or output name
#   PREFIX, PFX
pkg_prefix() {
  echo "${PFX[$1]:-$PREFIX}"
}

# The prefix the build in bdir installs its packages in; /pos for builds
# from before prefixes.
# Inputs:
#   bdir    active build directory
build_prefix() {
  local p
  p=$(build_info prefix)
  echo "${p:-/pos}"
}

# Read a metadata field from the active build's info file ($bdir/info).
# Inputs:
#   $1      info field key
#   bdir    active build directory
build_info() {
  info_get "$bdir" "$1"
}

# The commit the checkout is at, and clean or dirty: tracked files that
# differ from it, or files not added yet where the build reads its
# instructions; then "engine <commit>" when the engine is another
# checkout's, whose buildsys/ counts for clean. Recorded for the build,
# each package and each step made, so validate can tell that a build was
# made from one commit.
# Inputs:
#   base    path to the POS checkout
#   engine  path to the engine's checkout
tree_state() {
  local dirty state=clean
  dirty=$(git -C "$base" --no-optional-locks status --porcelain --untracked-files=no
          git -C "$base" --no-optional-locks status --porcelain -- VERSION outputs buildsys devtools "${RECIPES[@]}")
  [[ $engine == "$base" ]] ||
    dirty+=$(git -C "$engine" --no-optional-locks status --porcelain -- buildsys)
  [[ -z $dirty ]] || state=dirty
  if [[ $engine == "$base" ]]; then
    echo "$(git -C "$base" rev-parse HEAD) $state"
  else
    echo "$(git -C "$base" rev-parse HEAD) $state engine $(git -C "$engine" rev-parse HEAD)"
  fi
}

# Each producer of a build records what it made, in made/<name>
# (package-<package>, stage-<stage>, output-<output>), with the checkout
# it made it from (tree_state), and "unchecked" when its checks were
# skipped. A producer drops its record, and complete, before it starts
# (step_start), so a failed one leaves none. A default run that finishes
# records complete. rebuild drops the dropped packages' records and
# everything made from packages. validate reads only these records.
# Inputs:
#   $1      step record name
#   bdir    active build directory
step_start() {
  rm -f "$bdir/made/$1" "$bdir/made/complete"
}

# Record successful completion of a build step in $bdir/made/$1.
# Inputs:
#   $1      step record name
#   [$2]    optional status tag (e.g. "unchecked")
#   bdir    active build directory
step_made() {
  mkdir -p "$bdir/made"
  echo "$(tree_state)${2:+ $2}" >"$bdir/made/$1"
}

# Load the build in bdir: its pipeline (pos for builds from before
# pipelines), what it has built and its references.
# Inputs:
#   bdir    active build directory
# Outputs:
#   PIPELINE, PREFIX, BUILT[], TOOLCHAIN_REF, POS_REF, REF[], POSREF[], REF_REQ[]
build_load() {
  PIPELINE=$(build_info pipeline)
  PIPELINE=${PIPELINE:-pos}
  PREFIX=$(build_prefix)
  load_built
  build_references
  load_references
}

# The committed state of a source: builds and archives must match a commit.
# Inputs:
#   $1    source name
source_tree() {
  local path=${SRCPATH[$1]}
  if [[ -n $(git -C "$base" status --porcelain --untracked-files=no -- "$path" "$path.upstream") ]]; then
    die "$path has uncommitted changes; commit them before building"
  fi
  git -C "$base" rev-parse "HEAD:$path"
}

# Return 0 if a source has a prepare recipe: prepare.sh of the package
# named after it.
# Inputs:
#   $1    source name
has_prepare() {
  [[ -n ${PKGDIR[$1]:-} && -f $base/${PKGDIR[$1]}/prepare.sh ]]
}

# Print the source's committed .upstream metadata from HEAD.
# Inputs:
#   $1    source name
upstream_info() {
  git -C "$base" show "HEAD:${SRCPATH[$1]}.upstream" 2>/dev/null ||
    die "${SRCPATH[$1]}.upstream is not committed; prepare reads it from HEAD"
}

# The recipe directories, pos/<tree>/packages, as step_run mounts: recipes
# source each other's.
# Outputs:
#   RECIPE_MOUNTS (array of ro:<dir>)
recipe_mounts() {
  local d
  RECIPE_MOUNTS=()
  for d in "$base"/pos/*/packages; do
    RECIPE_MOUNTS+=(ro:"$d")
  done
}

# The key of a prepared tree: everything that goes into it.
# Inputs:
#   $1    source name
prepare_key() {
  local s=$1 w
  {
    source_tree "$s"
    upstream_info "$s"
    cat "$base/${PKGDIR[$s]}/prepare.sh" "$engine/buildsys/prepare.sh"
    echo "${PREQ[$s]}"
    # What prepare generates with is part of it; fedora's tools are the
    # tools image's, which keys never had.
    [[ $TOOLS_REF == none ]] || echo "tools $TOOLS_REF"
    if [[ -f $base/${SRCPATH[$s]}/bootstrap.conf || -x $base/${SRCPATH[$s]}/autopull.sh ]]; then
      source_tree gnulib
    fi
    for w in ${WSRC[$s]}; do
      source_tree "$w"
    done
  } | sha256sum | cut -c1-16
}

# Prepare a source unless a tree with the same key exists. Sets PREPARED to
# the prepared tree. Prepare has network: it fetches what upstream's
# release process does. It sees the committed source (prepare recipes
# compare with it), gnulib, and the committed sources of the package's
# with-sources, which upstream's bootstrap may take files from (tar's and
# cpio's paxutils).
# Inputs:
#   $1    source name
# Outputs:
#   PREPARED (path to prepared source directory in $sources/$s/$key)
prepare_source() {
  local s=$1 key dir log hbase w with_dirs= gnulib=''
  local -a mounts
  key=$(prepare_key "$s") || exit 1
  dir=$sources/$s/$key
  PREPARED=$dir
  [[ -f $dir.done ]] && return
  log=$bdir/logs/prepare-$s.log
  hbase=$(host_path "$base")
  rm -rf "$dir" "$dir.tmp"
  mkdir -p "$dir.tmp"
  git -C "$base" archive --format=tar "HEAD:${SRCPATH[$s]}" | tar -x -C "$dir.tmp"
  upstream_info "$s" >"$dir.upstream"
  recipe_mounts
  mounts=(net ro:"$engine/buildsys" "${RECIPE_MOUNTS[@]}" ro:"$base/${SRCPATH[$s]}" rw:"$dir.tmp" ro:"$dir.upstream")
  # The build tools of an extras reference: /pos and their prefix as a
  # package build has them, without a package's own environment.
  # Its own environment: prepare runs within a package's build_one.
  local root='' scripts=''
  local -a ENV=() MISSING=()
  local -A TOOLENV=()
  if [[ $TOOLS_REF != none ]]; then
    root=$bdir/roots/prepare-$s
    env_of || die "prepare $s: build tools unresolved: ${MISSING[*]}"
    local p=prepare-$s q
    root_compose "$root"
    root_mounts "$root"
    mounts+=("${ROOT_MOUNTS[@]}")
    for q in $(env_scripts); do
      scripts+=" $(env_script "$q" "$hbase")"
    done
  fi
  if [[ -n ${SRCPATH[gnulib]:-} && -d $base/${SRCPATH[gnulib]} ]]; then
    gnulib=$hbase/${SRCPATH[gnulib]}
    mounts+=(ro:"$base/${SRCPATH[gnulib]}")
  fi
  for w in ${WSRC[$s]}; do
    mounts+=(ro:"$base/${SRCPATH[$w]}")
    with_dirs+=" $w=$hbase/${SRCPATH[$w]}"
  done
  title "prepare $s"
  echo "=== prepare $s ($key) ===" | tee "$log"
  step_run "prepare-$s" "${mounts[@]}" -- env \
    POS_SOURCE="$s" \
    POS_RECIPE_DIR="$hbase/${PKGDIR[$s]}" \
    POS_SRC_DIR="$hbase/${SRCPATH[$s]}" \
    POS_GNULIB_DIR="$gnulib" \
    POS_PREP_DIR="$(host_path "$dir.tmp")" \
    POS_UPSTREAM="$(host_path "$dir.upstream")" \
    POS_WITH_SRC_DIRS="${with_dirs# }" \
    POS_TOOLS_PREFIX="$(tools_prefix)" \
    POS_ENV_SCRIPTS="${scripts# }" \
    bash "$(host_path "$engine/buildsys/prepare.sh")" 2>&1 | tee -a "$log"
  [[ -z $root ]] || rm -rf "$root"
  mv "$dir.tmp" "$dir"
  touch "$dir.done"
}

# The release archive of a source in the download directory, named as
# upstream names it.
# Inputs:
#   $1    source name
archive_file() {
  local url
  read -r url _ <<<"${ARCHIVE[$1]}"
  echo "$downloads/${url##*/}"
}

# The patches of a source from a release archive: patches/*.patch of its
# package directory, in name order.
# Inputs:
#   $1    source name
archive_patches() {
  local f
  for f in "$base/${PKGDIR[$1]}"/patches/*.patch; do
    [[ -f $f ]] && echo "$f"
  done
  return 0
}

# Download a source's release archive into the download directory, unless
# it is there. What is there or arrives must have the sha256 of the meta:
# a file that does not is left for the user to look at, never replaced.
# Inputs:
#   $1    source name
fetch_archive() {
  local s=$1 url sha f have
  read -r url sha <<<"${ARCHIVE[$s]}"
  f=$(archive_file "$s")
  if [[ ! -f $f ]]; then
    mkdir -p "$downloads"
    title "download $s"
    echo "=== download $s: $url ==="
    step_run "download-$s" net rw:"$downloads" -- \
      curl -fL --retry 3 --no-progress-meter -o "$(host_path "$f.tmp")" "$url"
    have=$(sha256sum "$f.tmp" | cut -d' ' -f1)
    [[ $have == "$sha" ]] || die "$s: $url has sha256 $have, not ${PKGDIR[$s]}/meta's $sha; kept as $f.tmp"
    mv "$f.tmp" "$f"
  fi
  have=$(sha256sum "$f" | cut -d' ' -f1)
  [[ $have == "$sha" ]] || die "$s: $f has sha256 $have, not ${PKGDIR[$s]}/meta's $sha"
}

# The key of an unpacked release archive: the archive and the patches.
# Inputs:
#   $1    source name
unpack_key() {
  local f
  {
    echo "${ARCHIVE[$1]}"
    while read -r f; do
      echo "${f##*/}"
      cat "$f"
    done < <(archive_patches "$1")
  } | sha256sum | cut -c1-16
}

# Unpack a source's release archive, downloaded if it is not yet, and
# apply its patches, unless a tree with the same key exists. The archive
# holds one top directory, which becomes the tree. Sets UNPACKED to the
# tree.
# Inputs:
#   $1    source name
# Outputs:
#   UNPACKED (path to the tree in $sources/$s/$key)
unpack_source() {
  local s=$1 key dir f p
  local -a patches=() mounts
  key=$(unpack_key "$s")
  dir=$sources/$s/$key
  UNPACKED=$dir
  [[ -f $dir.done ]] && return
  fetch_archive "$s"
  f=$(archive_file "$s")
  while read -r p; do
    patches+=("$(host_path "$p")")
  done < <(archive_patches "$s")
  rm -rf "$dir" "$dir.tmp"
  mkdir -p "$dir.tmp"
  mounts=(ro:"$f" rw:"$dir.tmp")
  ((${#patches[@]} == 0)) || mounts+=(ro:"$base/${PKGDIR[$s]}/patches")
  title "unpack $s"
  echo "=== unpack $s ($key) ==="
  # shellcheck disable=SC2016
  step_run "unpack-$s" "${mounts[@]}" -- bash -euo pipefail -c '
  f=$1 dir=$2
  shift 2
  tops=$(tar -tf "$f" | cut -d/ -f1 | sort -u | wc -l)
  [[ $tops == 1 ]] || { echo "${f##*/}: $tops top directories, not one" >&2; exit 1; }
  tar -xf "$f" -C "$dir" --strip-components=1 --no-same-owner
  cd "$dir"
  for p; do
    echo "patch ${p##*/}"
    patch -p1 -s --no-backup-if-mismatch <"$p"
  done
  ' unpack "$(host_path "$f")" "$(host_path "$dir.tmp")" "${patches[@]}"
  mv "$dir.tmp" "$dir"
  touch "$dir.done"
}

# Path to the installed package metadata file that marks a package built.
# Inputs:
#   $1      package name
#   bdir    active build directory
#   PREFIX  the build's prefix (build_prefix), PFX
marker() {
  echo "$bdir/dest/$1$(pkg_prefix "$1")/lib/pos/packages/$1/meta"
}

# Populate BUILT[] for every package whose marker exists in $bdir.
# Inputs:
#   PKGS, bdir
# Outputs:
#   BUILT[]
load_built() {
  local p
  BUILT=()
  for p in "${PKGS[@]}"; do
    [[ -f $(marker "$p") ]] && BUILT[$p]=1
  done
  return 0
}

# Write the package metadata into its staging tree. It is installed with
# the package, so a prefix tree records what it contains
# (<prefix>/lib/pos/packages/<package>). The meta file is written last: its
# presence marks the package built. The version is the source's
# (source_of), an output's its main package's.
# Inputs:
#   $1      package or output name
#   bdir    active build directory
#   PREFIX  the build's prefix, PFX
#   SOURCE_ID, SOURCE_VER, WITH_SOURCE_IDS, BUILD_KEY, CACHED_FROM (build_one)
pkg_record() {
  local p=$1 dest=$bdir/dest/$1 dir extra s pre rel content
  pre=$(pkg_prefix "$p")
  rel=${pre#/}
  [[ -d $dest$pre ]] || die "$p: nothing installed into $dest$pre"
  extra=$(cd "$dest" && find . -mindepth 1 -path "./$rel" -prune -o ! -type d -print)
  if [[ -n $extra ]]; then
    echo "warning: $p installed paths outside $pre:" >&2
    echo "$extra" >&2
  fi
  # <prefix>/lib is the only library directory (BUILD.md "Library
  # directory"). lib64 comes from build tools that look at the tools
  # image's /usr/lib64 (meson, cmake GNUInstallDirs, Fedora's gcc).
  extra=$(find "$dest$pre" -mindepth 1 -maxdepth 1 \( -name lib64 -o -name lib32 -o -name libx32 \) -print)
  [[ -z $extra ]] || die "$p: installed into $(echo "$extra" | xargs -n1 basename | xargs); set libdir to $pre/lib"
  dir=$dest$pre/lib/pos/packages/$p
  mkdir -p "$dir"
  # Files are replaced, not written to: a tree from the cache shares them
  # with the cache (cache_restore).
  (cd "$dest" && find "$rel" -mindepth 1 ! -type d ! -path "$rel/lib/pos/packages/*" | sed 's|^|/|' | sort) >"$dir/files.tmp"
  mv "$dir/files.tmp" "$dir/files"
  # A build that takes the package from a reference sets up with it.
  if [[ -f $base/${PKGDIR[$p]}/env.sh ]]; then
    cp "$base/${PKGDIR[$p]}/env.sh" "$dir/env.sh.tmp"
    mv "$dir/env.sh.tmp" "$dir/env.sh"
  fi
  content=$(content_hash "$p")
  {
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e '/^version[[:space:]]/d' "$base/${PKGDIR[$p]}/meta"
    [[ -z ${SOURCE_VER:-} ]] || echo "version $SOURCE_VER"
    echo "build $id"
    echo "build-key $BUILD_KEY"
    echo "content $content"
    [[ -z ${CACHED_FROM:-} ]] || echo "cached-from $CACHED_FROM"
    echo "build-source ${SRC[$(build_of "$p")]} ${SOURCE_ID:-}"
    for s in "${WITH_SOURCE_IDS[@]}"; do
      echo "build-with-source $s"
    done
    echo "build-env ${ENV[*]}"
    echo "build-tools $TOOLS_ID"
    echo "build-toolchain-reference $TOOLCHAIN_REF"
    echo "build-pos-reference $POS_REF"
    echo "build-tools-reference $TOOLS_REF"
    echo "built $(date -u +%FT%TZ)"
  } >"$dir/meta.tmp"
  mv "$dir/meta.tmp" "$dir/meta"
  step_made "package-$p"
}

# The content of a package's staging tree: every path with its type, mode
# and link target, and every file's hash; all but the meta, which names
# the build. Packages built against it are keyed by it (env_key), so a
# package built again that installs the same files rebuilds nothing.
# Inputs:
#   $1    package or output name
#   bdir, PREFIX, PFX
# Outputs:
#   the content hash, 16 hex digits
content_hash() {
  local meta
  meta=.$(pkg_prefix "$1")/lib/pos/packages/$1/meta
  (cd "$bdir/dest/$1" &&
     find . -mindepth 1 ! -path "$meta" -printf '%y %m %p %l\n' | sort &&
     find . -type f ! -path "$meta" -print0 | sort -z | xargs -0 -r sha256sum) |
    sha256sum | cut -c1-16
}

# Store a package build in the cache, $cache/<package>/<key>: the
# staging and debug trees of the package and its outputs (dest/, debug/),
# hard-linked, its log, and from, the build that compiled it. Staging
# trees are not changed once recorded (pkg_record replaces its files), so
# builds and the cache share them. An entry replaces one of the same key.
# Inputs:
#   $1    package name
#   BUILD_KEY, bdir, id
cache_store() {
  local p=$1 dir=$cache/$1/$BUILD_KEY q
  rm -rf "$dir.tmp"
  mkdir -p "$dir.tmp/dest" "$dir.tmp/debug"
  for q in "$p" ${OUTS[$p]}; do
    cp -al "$bdir/dest/$q" "$dir.tmp/dest/"
    [[ ! -d $bdir/debug/$q ]] || cp -al "$bdir/debug/$q" "$dir.tmp/debug/"
  done
  cp "$bdir/logs/$p.log" "$dir.tmp/log"
  echo "$id" >"$dir.tmp/from"
  rm -rf "$dir"
  mv "$dir.tmp" "$dir"
}

# Take a package build from the cache (cache_store) into the build: the
# staging and debug trees of the package and its outputs, hard-linked.
# Returns 1 when the cache has no build of its key, or run --no-cache.
# Inputs:
#   $1    package name
#   BUILD_KEY, bdir, NO_CACHE
# Outputs:
#   CACHED_FROM (the build that compiled it)
cache_restore() {
  local p=$1 dir=$cache/$1/$BUILD_KEY q
  [[ -z $NO_CACHE && -f $dir/from ]] || return 1
  for q in "$p" ${OUTS[$p]}; do
    rm -rf "${bdir:?}/dest/$q" "${bdir:?}/debug/$q"
    cp -al "$dir/dest/$q" "$bdir/dest/"
    [[ ! -d $dir/debug/$q ]] || cp -al "$dir/debug/$q" "$bdir/debug/"
  done
  CACHED_FROM=$(<"$dir/from")
}

# The staging tree of a package in the environment, a root holding its
# prefix: this build's, or a reference's (<name>@ref, <name>@pos,
# <name>@tools).
# Inputs:
#   $1    environment entry (<pkg>, <pkg>@ref, <pkg>@pos or <pkg>@tools)
#   TOOLCHAIN_REF, POS_REF, TOOLS_REF
env_tree() {
  env_tree_v "$1"
  echo "$ENVTREE"
}

# env_tree into ENVTREE, without a subshell (env_script, for each entry).
env_tree_v() {
  case $1 in
    *@ref) ENVTREE=$refs/$TOOLCHAIN_REF/dest/${1%@ref} ;;
    *@pos) ENVTREE=$refs/$POS_REF/dest/${1%@pos} ;;
    *@tools) ENVTREE=$refs/$TOOLS_REF/dest/${1%@tools} ;;
    *) ENVTREE=$bdir/dest/$1 ;;
  esac
}

# The prefix of an environment entry's package: a reference's
# (ref_prefix), or this build's; /pos for one whose meta says so (PFX).
# Inputs:
#   $1    environment entry (<pkg>, <pkg>@ref, <pkg>@pos or <pkg>@tools)
#   TOOLCHAIN_REF, POS_REF, TOOLS_REF, PREFIX, PFX
env_prefix() {
  env_prefix_v "$1"
  echo "$ENVPFX"
}

# env_prefix into ENVPFX, without a subshell for the build's references
# (REFPFX).
env_prefix_v() {
  local p=${1%@*} ref
  if [[ -n ${PFX[$p]:-} ]]; then
    ENVPFX=${PFX[$p]}
    return
  fi
  case $1 in
    *@ref) ref=$TOOLCHAIN_REF ;;
    *@pos) ref=$POS_REF ;;
    *@tools) ref=$TOOLS_REF ;;
    *) ENVPFX=$PREFIX; return ;;
  esac
  ENVPFX=${REFPFX[$ref]:-$(ref_prefix "$ref")}
}

# The prefix of the build tools from an extras reference, or nothing
# (fedora's, in the tools image).
# Inputs:
#   TOOLS_REF
tools_prefix() {
  [[ $TOOLS_REF == none ]] || ref_prefix "$TOOLS_REF"
}

# The build tools, for messages: fedora, or the extras reference and its
# number of packages.
# Inputs:
#   TOOLS_REF, TOOLSREF
tools_name() {
  if [[ $TOOLS_REF == none ]]; then
    echo fedora
  else
    echo "$TOOLS_REF (${#TOOLSREF[@]} packages)"
  fi
}

# The packages of the environment a package build may link (pkg.sh:
# _pkg_linkcheck): all but those only the build tools brought (TOOLENV),
# by name, and the build's own outputs.
# Inputs:
#   $1    package name
#   ENV, TOOLENV, OUTS
env_linkable() {
  local q
  for q in "${ENV[@]}"; do
    [[ -n ${TOOLENV[$q]:-} ]] || echo "${q%@*}"
  done
  echo "$1" ${OUTS[$1]}
}

# Compose the root of a package build: the trees of the packages in ENV
# hard-linked into one directory, whose top directories (pos, and apps for
# extras) the build container mounts read-only (root_mounts). /pos is
# there even when empty. A path has one owner: cp fails on a path another
# package of the environment already put there.
# Inputs:
#   $1     destination root directory ($bdir/roots/$p)
#   ENV    resolved package environment array
root_compose() {
  local root=$1 q
  rm -rf "$root"
  mkdir -p "$root/pos"
  for q in "${ENV[@]}"; do
    case ${KIND[${q%@*}]} in
      package|output)
        cp -al --update=none-fail "$(env_tree "$q")/." "$root/" ||
          die "$p: ${q%@*} ships a path another package of the environment ships" ;;
    esac
  done
}

# The mounts of a composed root (root_compose): each top directory at its
# place, read-only.
# Inputs:
#   $1    composed root directory
# Outputs:
#   ROOT_MOUNTS (array of ro:<dir>:/<name>)
root_mounts() {
  local d
  ROOT_MOUNTS=()
  for d in "$1"/*/; do
    d=${d%/}
    ROOT_MOUNTS+=(ro:"$d:/${d##*/}")
  done
}



# The time of a release archive, for SOURCE_DATE_EPOCH: its newest
# member's, as upstream made it. Kept beside the unpacked tree, as
# <tree>.epoch, since listing an archive takes a while; a tree unpacked
# without one has its archive downloaded again, if it is gone.
# Inputs:
#   $1    source name
#   UNPACKED  the source's unpacked tree (unpack_source)
archive_epoch() {
  local t
  if [[ ! -s $UNPACKED.epoch ]]; then
    fetch_archive "$1" >&2
    t=$(TZ=UTC tar --full-time -tvf "$(archive_file "$1")" | awk '{print $4 " " $5}' | sort | tail -n 1) ||
      die "$1: cannot list $(archive_file "$1")"
    TZ=UTC date -d "${t:?}" +%s >"$UNPACKED.epoch.tmp"
    mv "$UNPACKED.epoch.tmp" "$UNPACKED.epoch"
  fi
  cat "$UNPACKED.epoch"
}

# The tree a source is built from, its identity for the package metadata
# and the source archives (the unpacked or prepared tree's key, or the
# committed tree), its time, which builds take as SOURCE_DATE_EPOCH: the
# archive's (archive_epoch), else the last commit of the source's path, so
# builds of the same source write the same dates; and its version, which
# package records carry: a release's (meta version), else the snapshot of
# its .upstream, as prepare names it (prep_version). None of either for a
# package without a source, and no version for a source without a
# .upstream (pos-integration).
# Inputs:
#   $1    source name
# Outputs:
#   SOURCE_DIR, SOURCE_KEY, SOURCE_EPOCH, SOURCE_VERSION
source_of() {
  local s=$1
  SOURCE_DIR=$base/${SRCPATH[$s]}
  if [[ -n ${ARCHIVE[$s]:-} ]]; then
    unpack_source "$s"
    SOURCE_DIR=$UNPACKED
    SOURCE_KEY=$(basename "$UNPACKED")
    SOURCE_EPOCH=$(archive_epoch "$s") || exit 1
    SOURCE_VERSION=${VERSION[$s]}
    return 0
  fi
  SOURCE_EPOCH=$(git -C "$base" log -1 --format=%ct HEAD -- "${SRCPATH[$s]}")
  # A source of the project itself (pos-integration) has no .upstream, and no version.
  SOURCE_VERSION=$({ git -C "$base" show "HEAD:${SRCPATH[$s]}.upstream" 2>/dev/null || true; } |
    awk '{v[$1] = $2} END {if (v["ref"] != "" && v["commit"] != "" && v["date"] != "")
      print v["ref"] "-" substr(v["date"], 1, 4) substr(v["date"], 6, 2) substr(v["date"], 9, 2) "-" substr(v["commit"], 1, 12)}')
  if has_prepare "$s"; then
    prepare_source "$s"
    SOURCE_DIR=$PREPARED
    SOURCE_KEY=$(basename "$PREPARED")
  elif [[ -d $SOURCE_DIR ]]; then
    SOURCE_KEY=$(source_tree "$s")
  else
    SOURCE_KEY='' SOURCE_EPOCH='' SOURCE_VERSION=''
  fi
}

# The files of a recipe directory with their hashes, as the working tree
# has them: builds use the recipes of the checkout (tree_state records
# whether they are committed).
# Inputs:
#   $1    recipe directory, relative to base
recipe_hash() {
  (cd "$base/$1" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum)
}

# The identity of an environment entry for a build key (build_key): a
# reference's package by its reference, this build's by the content in its
# meta (content_hash); one built before content hashes by its build-key,
# and one built before build keys by when it was built, which no other
# build shares. A profile installs nothing; what it requires is in the
# environment itself. A package no longer in the trees is gone.
# Inputs:
#   $1    environment entry (<pkg>, <pkg>@ref, <pkg>@pos or <pkg>@tools)
#   TOOLCHAIN_REF, POS_REF, TOOLS_REF, bdir
env_key() {
  case $1 in
    *@ref) echo "ref $TOOLCHAIN_REF" ;;
    *@pos) echo "ref $POS_REF" ;;
    *@tools) echo "ref $TOOLS_REF" ;;
    *)
      [[ ${KIND[$1]:-} == package || ${KIND[$1]:-} == output ]] || { echo "${KIND[$1]:-gone}"; return; }
      awk '$1 == "content" {c = $2} $1 == "build-key" {k = $2} $1 == "built" {b = $2}
           END {print (c != "" ? "content " c : k != "" ? "key " k : "built " b)}' "$(marker "$1")" ;;
  esac
}

# The key of a source tree as source_of gives it, without preparing,
# downloading or unpacking it, and its time when the key does not fix it:
# the time of a release archive is the archive's, which its key names.
# Inputs:
#   $1    source name
# Outputs:
#   prints "<key> <time>"
source_id() {
  local s=$1
  if [[ -n ${ARCHIVE[$s]:-} ]]; then
    echo "$(unpack_key "$s") -"
    return
  fi
  if has_prepare "$s"; then
    printf '%s ' "$(prepare_key "$s")"
  elif [[ -d $base/${SRCPATH[$s]} ]]; then
    printf '%s ' "$(source_tree "$s")"
  else
    printf -- '- '
  fi
  git -C "$base" log -1 --format=%ct HEAD -- "${SRCPATH[$s]}"
}

# The Fedora packages of the tools image that the recipes' host-requires
# name, for build keys (build_key): each name with the packages that
# provide it (name-version-release.arch), or - when none does (a
# host-requires the build tools replace). A key names the versions of the
# Fedora packages its build uses, not the image: each build makes an image
# of its own, with the Fedora packages of the day.
# Inputs:
#   bdir, PKGS, HREQ
# Outputs:
#   FEDORA (host-requires name -> its packages)
tools_versions() {
  local p n v
  FEDORA=()
  # shellcheck disable=SC2016
  while read -r n v; do
    FEDORA[$n]=$v
  done < <(for p in "${PKGS[@]}"; do echo "${HREQ[$p]}"; done | xargs -n1 | sort -u |
             host_podman run --rm -i --network=none "$(build_info tools-image)" bash -c '
               while read -r n; do
                 if v=$(rpm -q --whatprovides --qf "%{NEVRA}\n" "$n" 2>/dev/null); then
                   echo "$n $(sort <<<"$v" | xargs)"
                 else
                   echo "$n -"
                 fi
               done')
}

# The key of a package build: a hash of everything build_one hands the
# build container (step_run). A build has no network, so two builds with
# the same key build the same package. Left out: the paths of the
# checkout and of the build directory (POS_BASE, POS_DEST_DIR), which
# builds must not depend on (see build_one).
#   - the source: its tree's key and time (source_id), the with-sources';
#   - the recipe: the package's directory, the recipe of its source, which a
#     bootstrap recipe sources (util-linux-bootstrap), and buildsys/pkg.sh;
#   - the environment: each entry's identity (env_key), and the env.sh
#     scripts of this build's packages in it;
#   - the build tools: the tools reference, and the Fedora packages
#     (tools_versions) that the package's host-requires name and those of
#     the host and profile packages of its environment (host-base, with
#     Fedora's tools);
#   - the prefixes.
# Inputs:
#   $1    package name
#   ENV (env_of, or as the package was built: stale_check), FEDORA,
#   TOOLS_REF, PREFIX
# Outputs:
#   the key, 16 hex digits
build_key() {
  local p=$1 q d
  {
    echo "source ${SRC[$p]} $(source_id "${SRC[$p]}")"
    for q in ${WSRC[$p]}; do
      echo "with-source $q $(source_id "$q")"
    done
    for d in $(printf '%s\n' "${PKGDIR[$p]}" "${PKGDIR[${SRC[$p]}]:-}" | sed '/^$/d' | sort -u); do
      echo "recipe $d"
      recipe_hash "$d"
    done
    sha256sum <"$engine/buildsys/pkg.sh"
    for q in "${ENV[@]}"; do
      echo "env $q $(env_key "$q")"
    done
    # The env.sh of this build's packages (env_script), their recipes'; a
    # reference's is in its tree, which the reference names.
    for q in "${ENV[@]}"; do
      d=$base/${PKGDIR[$q]:-}/env.sh
      is_ref "$q" || [[ -z ${PKGDIR[$q]:-} || ! -f $d ]] || echo "env-script $q $(sha256sum <"$d")"
    done
    echo "tools $TOOLS_REF"
    for d in $(for q in "$p" "${ENV[@]}"; do
                 [[ $q == "$p" || ${KIND[$q]:-} == host || ${KIND[$q]:-} == profile ]] || continue
                 echo "${HREQ[$q]:-}"
               done | xargs -n1 | sort -u); do
      echo "fedora $d ${FEDORA[$d]:--}"
    done
    echo "prefix $PREFIX $(sdk_prefix) $(tools_prefix)"
    for q in "$p" ${OUTS[$p]}; do
      echo "output $q $(pkg_prefix "$q")"
    done
  } | sha256sum | cut -c1-16
}

# Whether a package of this build is stale: built before its inputs
# changed, or against a package of this build that is stale. Its key is
# computed with the environment it was built with (its meta's build-env),
# not the one it would resolve now: a package built against a bootstrap
# package (systemd against util-linux-bootstrap) stays built against it.
# A change to what it requires changes its meta, which is in its key. Kept:
# one built before build keys, which cannot be checked. Packages of the
# environment are checked first; a stale one makes the package stale even
# when its key matches, since that key names what it installed before.
# Inputs:
#   $1      package name
#   BUILT, bdir, FEDORA
# Outputs:
#   STALE[$1] (why), CHECKED[$1]
stale_one() {
  local p=$1 meta key e q
  [[ -z ${CHECKED[$p]:-} ]] || return 0
  CHECKED[$p]=1
  meta=$(marker "$p")
  key=$(awk '$1 == "build-key" {print $2}' "$meta")
  [[ -n $key ]] || return 0
  local -a ENV
  read -ra ENV < <(awk '$1 == "build-env" {$1 = ""; print}' "$meta")
  for e in "${ENV[@]}"; do
    [[ $e != *@* ]] || continue
    q=$e
    [[ ${KIND[$q]:-} != output ]] || q=${PARENT[$q]}
    [[ ${KIND[$q]:-} == package ]] || continue
    # Dropped (rebuild): built again, and what it installs is not known yet.
    if [[ -z ${BUILT[$q]:-} ]]; then
      STALE[$p]="built against $q, which is built again"
      return 0
    fi
    stale_one "$q"
    if [[ -n ${STALE[$q]:-} ]]; then
      STALE[$p]="built against $q"
      return 0
    fi
  done
  [[ $(build_key "$p") == "$key" ]] || STALE[$p]="its inputs changed"
}

# The stale packages of this build (stale_one), which run builds again:
# they are not built (BUILT), and neither are their outputs.
# Inputs:
#   BUILT, bdir, FEDORA
# Outputs:
#   STALE (package -> why), BUILT
stale_check() {
  local p q
  STALE=() CHECKED=()
  for p in "${!BUILT[@]}"; do
    [[ ${KIND[$p]:-} != package ]] || stale_one "$p"
  done
  for p in "${!STALE[@]}"; do
    for q in "$p" ${OUTS[$p]}; do
      unset "BUILT[$q]"
    done
  done
}

# Drop a package and its outputs from the build: their trees and records,
# and what was made from packages (stages, outputs, complete).
# Inputs:
#   $1      package name
#   bdir, id
drop_package() {
  local q
  for q in "$1" ${OUTS[$1]}; do
    rm -rf "${bdir:?}/dest/$q" "${bdir:?}/debug/$q" "${bdir:?}/made/package-$q"
    unset "BUILT[$q]"
  done
  find "$bdir/made" -mindepth 1 -maxdepth 1 ! -name 'package-*' -delete 2>/dev/null || true
}

# Drop the stale packages of this build (stale_check), so run builds them
# again, from the cache when a build of their key is there. run adds them
# to its targets: what was built in the build stays built in it.
# Inputs:
#   BUILT, bdir, id, FEDORA
stale_drop() {
  local p
  stale_check
  for p in $(printf '%s\n' "${!STALE[@]}" | sort); do
    echo "$p: ${STALE[$p]}; building it again"
    drop_package "$p"
  done
}

# Build a single package and its declared outputs inside an isolated build
# container, then record their installed files and metadata.
# Inputs:
#   $1      package name
#   bdir    active build directory
# Outputs:
#   BUILT[$p] and BUILT[$q] for each output q in OUTS[$p]
build_one() {
  local p=$1 q scripts log root env_files=
  local hbase hbdir src_dir s epoch with_dirs='' outpfx=''
  hbase=$(host_path "$base")
  env_of "$p" || die "$p: unresolved: ${MISSING[*]}"
  scripts=
  for q in $(env_scripts); do
    scripts+=" ${q%@*}"
    env_files+=" $(env_script "$q" "$hbase")"
  done
  scripts=${scripts# }
  log=$bdir/logs/$p.log
  root=$bdir/roots/$p
  hbdir=$(host_path "$bdir")
  for q in "$p" ${OUTS[$p]}; do
    step_start "package-$q"
  done
  for q in ${OUTS[$p]}; do
    outpfx+=" $q=$(pkg_prefix "$q")"
  done
  source_of "${SRC[$p]}"
  src_dir=$SOURCE_DIR
  SOURCE_ID=$SOURCE_KEY SOURCE_VER=$SOURCE_VERSION
  epoch=$SOURCE_EPOCH
  # The package's own inputs: the recipes (they source each other's),
  # its source trees, and the build's build, dest and debug directories.
  # The source trees are at /src/<source> and the build directory at
  # /build, whatever the checkout's path and the build's ID: compilers
  # write the paths they build at into debug info, __FILE__ and libtool
  # archives, and two builds of the same sources should not differ in them.
  recipe_mounts
  local -a mounts=(ro:"$engine/buildsys" "${RECIPE_MOUNTS[@]}")
  [[ ! -d $src_dir ]] || mounts+=(ro:"$src_dir:/src/${SRC[$p]}")
  WITH_SOURCE_IDS=()
  for s in ${WSRC[$p]}; do
    source_of "$s"
    mounts+=(ro:"$SOURCE_DIR:/src/$s")
    with_dirs+=" $s=/src/$s"
    WITH_SOURCE_IDS+=("$s $SOURCE_KEY")
  done
  mounts+=(rw:"$bdir/build:/build" rw:"$bdir/dest" rw:"$bdir/debug")
  BUILD_KEY=$(build_key "$p") || exit 1
  CACHED_FROM=

  # A build of the same key in the cache is this build.
  if cache_restore "$p"; then
    echo "=== $p: from the cache, built by $CACHED_FROM ===" | tee "$log"
    echo "build-key: $BUILD_KEY (log: $cache/$p/$BUILD_KEY/log)" | tee -a "$log"
    for q in "$p" ${OUTS[$p]}; do
      pkg_record "$q"
      BUILT[$q]=1
    done
    return 0
  fi
  echo "=== $p: setup: ${scripts:-none} ===" | tee "$log"
  echo "env: ${ENV[*]}" | tee -a "$log"
  echo "build-key: $BUILD_KEY" | tee -a "$log"
  root_compose "$root"
  root_mounts "$root"
  step_run "$p" "${ROOT_MOUNTS[@]}" "${mounts[@]}" -- env \
    POS_BASE="$hbase" \
    POS_PACKAGE="$p" \
    POS_RECIPE_DIR="$hbase/${PKGDIR[$p]}" \
    POS_PREFIX="$PREFIX" \
    POS_SDK_PREFIX="$(sdk_prefix)" \
    POS_TOOLS_PREFIX="$(tools_prefix)" \
    POS_LINKABLE="$(env_linkable "$p" | xargs)" \
    POS_OUTPUT_PREFIXES="${outpfx# }" \
    POS_SRC_DIR="/src/${SRC[$p]}" \
    POS_WITH_SRC_DIRS="${with_dirs# }" \
    POS_BUILD_DIR="/build/$p" \
    ${epoch:+"SOURCE_DATE_EPOCH=$epoch"} \
    POS_DEST_DIR="$hbdir/dest/$p" \
    POS_DEBUG_DIR="$hbdir/debug/$p" \
    POS_OUTPUTS="${OUTS[$p]# }" \
    POS_ENV_SCRIPTS="${env_files# }" \
    bash "$(host_path "$engine/buildsys/pkg.sh")" 2>&1 | tee -a "$log"
  for q in "$p" ${OUTS[$p]}; do
    pkg_record "$q"
    BUILT[$q]=1
  done
  cache_store "$p"
  # Kept when the build fails, to look at.
  rm -rf "$root"
}

# Report which wanted packages have unresolved dependencies and exit 1.
# Inputs:
#   WANTED    array of unbuilt target/dependency packages
report_stuck() {
  local p
  echo "cannot build:" >&2
  for p in "${WANTED[@]}"; do
    env_of "$p" || echo "  $p: needs ${MISSING[*]}" >&2
  done
  exit 1
}

# CLI command: print the topological build plan and resolved environments.
# Inputs:
#   $@    [--new] [<stage>|<package>...]
cmd_plan() {
  local id= bdir n=0 t
  local -a args=()
  for t in "$@"; do
    case $t in
      --new) id="<new>" ;;
      -*) usage ;;
      *) args+=("$t") ;;
    esac
  done
  if [[ -z $id ]] && id=$(current_id); then
    bdir=$builds/$id
    build_load
    # The stale packages, which run builds again; the tools image is
    # needed for their keys.
    if host_podman image exists "$(build_info tools-image)"; then
      tools_versions
      stale_check
      for t in $(printf '%s\n' "${!STALE[@]}" | sort); do
        echo "$t: ${STALE[$t]}"
      done
    else
      echo "tools image $(build_info tools-image) is gone: stale packages not checked"
    fi
  else
    id="<new>"
    PREFIX=$(project_prefix "$(version_info HEAD - 000000000000)")
    references_choose
    load_references
  fi
  ((${#args[@]})) || mapfile -t args < <(pipeline_targets)
  bootstrap_check "${args[@]}"
  targets_expand "${args[@]}"
  targets_check "${TARGETS[@]}"
  TARGETS+=("${!STALE[@]}")
  echo "build $id ($PIPELINE)"
  echo "toolchain reference $TOOLCHAIN_REF (${#REF[@]} packages), pos reference $POS_REF (${#POSREF[@]} packages)," \
       "tools $(tools_name)"
  while next_package "${TARGETS[@]}"; do
    env_of "$NEXT"
    printf '%3d %-24s setup: %s\n' $((++n)) "$NEXT" "$(env_scripts | sed 's/@.*//' | xargs)"
    printf '    env: %s\n' "${ENV[*]}"
    for t in "$NEXT" ${OUTS[$NEXT]}; do
      BUILT[$t]=1
    done
  done
  wanted "${TARGETS[@]}"
  ((${#WANTED[@]} == 0)) || report_stuck
  ((n > 0)) || echo "nothing to build"
}

# Archive every source the build's packages were built from, as recorded in
# their metadata (build-source, build-with-source), and the build recipes.
# A source from a release archive is that archive as downloaded,
# pos-src-<archive>: the meta's sha256 checks it, and its patches are in
# the recipes. An engine of another checkout gets an archive of its own,
# pos-engine-<stem>.tar.zst.
# Inputs:
#   bdir, PKGS, KIND, BUILT
source_archives() {
  local p s key out commit stem spec
  local -a recipes=() specs=(outputs buildsys "${RECIPES[@]}" BUILD.md README.md)
  local -A seen=()
  for p in "${PKGS[@]}"; do
    [[ ${KIND[$p]} == package && -n ${BUILT[$p]:-} ]] || continue
    while read -r s key; do
      [[ -z ${seen[$s]:-} ]] || continue
      seen[$s]=1
      if [[ -z $key ]]; then
        echo "note: no source archive for $s: ${SRCPATH[$s]:-its source} is not in the repository"
        continue
      fi
      if [[ -n ${ARCHIVE[$s]:-} ]]; then
        out=$bdir/pos-src-$(basename "$(archive_file "$s")")
        [[ -f $out ]] || { cp "$(archive_file "$s")" "$out.tmp" && mv "$out.tmp" "$out"; }
        echo "$out"
        continue
      fi
      out=$bdir/pos-src-$s-${key:0:16}.tar.zst
      [[ -f $out ]] && continue
      if [[ -d $sources/$s/$key ]]; then
        tar --zstd -cf "$out.tmp" -C "$sources/$s" --transform "s,^$key,$s," "$key"
      else
        git -C "$base" archive --format=tar --prefix="$s/" "$key" | zstd -q -o "$out.tmp"
      fi
      mv "$out.tmp" "$out"
      echo "$out"
    done < <(awk '$1 == "build-source" || $1 == "build-with-source" {print $2, $3}' "$(marker "$p")")
  done
  stem=$(build_stem "$bdir")
  [[ $engine == "$base" ]] || specs=(outputs "${RECIPES[@]}" BUILD.md README.md)
  # What the project has of them: git archive refuses a path it has not.
  for spec in "${specs[@]}"; do
    [[ -z $(git -C "$base" ls-files -- "$spec" | head -n1) ]] || recipes+=("$spec")
  done
  if [[ $engine != "$base" ]]; then
    commit=$(git -C "$engine" rev-parse HEAD)
    if [[ $commit != "$(build_info engine)" ]] ||
       [[ -n $(git -C "$engine" status --porcelain --untracked-files=no -- buildsys) ]]; then
      echo "warning: the engine differs from the commit the build started at; the engine archive holds HEAD" >&2
    fi
    out=$bdir/pos-engine-$stem.tar.zst
    git -C "$engine" archive --format=tar --prefix="pos-engine-$stem/" HEAD buildsys |
      zstd -q -f -o "$out.tmp"
    mv "$out.tmp" "$out"
    echo "$out"
  fi
  commit=$(git -C "$base" rev-parse HEAD)
  if [[ $commit != "$(build_info commit)" ]] ||
     [[ -n $(git -C "$base" status --porcelain --untracked-files=no -- "${recipes[@]}") ]]; then
    echo "warning: outputs, buildsys, recipes or stages differ from the commit the build started at;" \
         "the recipes archive holds HEAD" >&2
  fi
  out=$bdir/$project-recipes-$stem.tar.zst
  git -C "$base" archive --format=tar --prefix="$project-recipes-$stem/" HEAD \
    "${recipes[@]}" | zstd -q -f -o "$out.tmp"
  mv "$out.tmp" "$out"
  echo "$out"
}

# Build all wanted packages for the resolved targets in topological dependency order.
# Inputs:
#   $@    expanded target package names (TARGETS)
build_packages() {
  # The total is what is wanted now; it can shift a little as outputs and
  # obsoletes resolve.
  local n=0 total
  wanted "$@"
  total=${#WANTED[@]}
  while next_package "$@"; do
    title "$((++n))/$total $NEXT"
    build_one "$NEXT"
  done
  wanted "$@"
  ((${#WANTED[@]} == 0)) || report_stuck
}

# Assemble stage archives for the given stages and record made/stage-<stage>.
# Inputs:
#   $@    stage names to assemble
assemble_stages() {
  local t
  for t in "$@"; do
    title "assemble $t"
    step_start "stage-$t"
    "$engine/buildsys/assemble.sh" "$bdir" "$t" "$refs/$TOOLCHAIN_REF"
    step_made "stage-$t"
  done
}

# Primary OS build pipeline: build all required packages, assemble target stages,
# and emit source archives if enabled on the build.
# Inputs:
#   $@    target stage and/or package names
# Outputs:
#   STAGES_BUILT[]    array of stage names assembled during this run
build_os() {
  local t
  STAGES_BUILT=()
  build_packages "${TARGETS[@]}"
  for t in "$@"; do
    [[ -f $(stage_file "$t") ]] && STAGES_BUILT+=("$t")
  done
  assemble_stages "${STAGES_BUILT[@]}"
  if [[ $(build_info source-archives) == yes ]]; then
    title "source archives"
    source_archives
  fi
}

# CLI command: build target stages/packages, assemble stages, and make the
# outputs they can make.
# Inputs:
#   $@    [--new] [--source-archives] [--no-checks] [<stage>|<package>...]
cmd_run() {
  local new= archives=no t all=
  local -a args=()
  for t in "$@"; do
    case $t in
      --new) new=1 ;;
      --source-archives) archives=yes ;;
      --no-checks) CHECKS=no ;;
      --no-cache) NO_CACHE=1 ;;
      -*) usage ;;
      *) args+=("$t") ;;
    esac
  done
  if [[ $archives == yes && -z $new ]]; then
    die "--source-archives is chosen when a build is created; use it with --new"
  fi
  if [[ -n $new ]] || ! id=$(current_id); then
    build_new "$archives"
    echo "new build $id"
  fi
  bdir=$builds/$id
  [[ -n $(build_info tools-image) ]] ||
    die "build $id builds in toolboxes, which this buildsys no longer does; start another with run --new"
  build_versioned "$bdir"
  build_load
  echo "build $id ($PIPELINE), toolchain reference $TOOLCHAIN_REF (${#REF[@]} packages)," \
       "pos reference $POS_REF (${#POSREF[@]} packages), tools $(tools_name)"
  if ((${#args[@]} == 0)); then
    all=1
    mapfile -t args < <(pipeline_targets)
  fi
  bootstrap_check "${args[@]}"
  targets_expand "${args[@]}"
  targets_check "${TARGETS[@]}"
  tools_ensure
  TOOLS_ID=$(host_podman image inspect --format '{{.Id}}' "$(build_info tools-image)")
  tools_versions
  stale_drop
  TARGETS+=("${!STALE[@]}")

  title_init
  build_os "${args[@]}"
  local -a outputs
  mapfile -t outputs < <(outputs_of "${STAGES_BUILT[@]}")
  outputs_run "${outputs[@]}"
  [[ -z $all ]] || step_made complete
}

# Download, unpack and prepare the sources the targets are built from,
# ahead of a run (run does when it needs them), so the run can be offline.
# Uses the current build's tools image.
# Inputs:
#   $@    optional stage and/or package target names
cmd_prepare() {
  local p s
  local -a args=("$@")
  local -A seen=()
  id=$(current_id) || die "no current build; start one with run --new"
  bdir=$builds/$id
  PIPELINE=$(build_info pipeline)
  PIPELINE=${PIPELINE:-pos}
  title_init
  ((${#args[@]})) || mapfile -t args < <(pipeline_targets)
  targets_expand "${args[@]}"
  for p in "${TARGETS[@]}"; do
    p=$(build_of "$p")
    for s in ${SRC[$p]} ${WSRC[$p]}; do
      [[ -z ${seen[$s]:-} ]] || continue
      seen[$s]=1
      if [[ -n ${ARCHIVE[$s]:-} ]]; then
        unpack_source "$s"
        echo "$s: $UNPACKED"
      elif has_prepare "$s"; then
        prepare_source "$s"
        echo "$s: $PREPARED"
      fi
    done
  done
}

# Drop specified packages (and their outputs and downstream stage and output records)
# from the current build so a subsequent run rebuilds them.
# Inputs:
#   $@    package names to drop
cmd_rebuild() {
  local p q
  (($#)) || usage
  id=$(current_id) || die "no current build"
  bdir=$builds/$id
  for p in "$@"; do
    case ${KIND[$p]:-} in
      package) ;;
      output) die "$p is an output of ${PARENT[$p]}; rebuild ${PARENT[$p]}" ;;
      *) die "not a package: $p" ;;
    esac
    drop_package "$p"
    for q in "$p" ${OUTS[$p]}; do
      echo "$q: dropped from build $id"
    done
  done
}

# Print the current build's info, built packages, and pending packages.
cmd_status() {
  local p
  local -a built=()
  id=$(current_id) || die "no current build"
  bdir=$builds/$id
  cat "$bdir/info"
  build_load
  for p in "${PKGS[@]}"; do
    [[ -n ${BUILT[$p]:-} ]] && built+=("$p")
  done
  echo "built (${#built[@]}): ${built[*]}"
  local -a args
  mapfile -t args < <(pipeline_targets)
  targets_expand "${args[@]}"
  wanted "${TARGETS[@]}"
  echo "pending (${#WANTED[@]}): ${WANTED[*]}"
}

# Remove the tools container image and temporary composed roots for a build.
# Inputs:
#   [$1]    build ID (defaults to current_id)
cmd_clean() {
  id=${1:-$(current_id)} || die "no current build"
  if host_podman image exists "$(tools_image)"; then
    echo "removing image $(tools_image)"
    host_podman rmi "$(tools_image)" >/dev/null
  fi
  rm -rf "${builds:?}/$id/roots"
  echo "outputs are kept in $builds/$id"
}

# The builds prune keeps: the current one and the newest keep-builds
# others, by ID (a build's ID is the time it was created).
# Inputs:
#   builds, config(keep-builds)
# Outputs:
#   KEEP (build ID -> 1)
prune_keep() {
  local n b cur
  n=$(config keep-builds)
  [[ $n =~ ^[0-9]+$ ]] || die "keep-builds: not a number: $n"
  KEEP=()
  cur=$(current_id) && KEEP[$cur]=1
  for b in $(prune_builds_all | sort -r); do
    ((n > 0)) || break
    [[ -z ${KEEP[$b]:-} ]] || continue
    KEEP[$b]=1
    n=$((n - 1))
  done
}

# The IDs of the checkout's builds, work/builds/<id> (not current).
# Inputs:
#   builds
prune_builds_all() {
  local b
  for b in "$builds"/*/; do
    b=${b%/}
    [[ -L $b ]] || echo "${b##*/}"
  done
}

# What prune removes, listed and counted; removed unless -n. Sizes count
# files a build or the cache shares too, which removing one frees not, and
# leave out what the user cannot read (made as root in a container).
# Inputs:
#   $1      what (builds, references, sources, cache)
#   $@      the paths
#   DRY     -n
prune_remove() {
  local what=$1 f
  local -a host=()
  shift
  if (($# == 0)); then
    echo "$what: nothing to remove"
    return 0
  fi
  printf '  %s\n' "${@#"$base"/work/}"
  echo "$what: $# to remove, $(du -sch "$@" 2>/dev/null | tail -n 1 | cut -f1)${DRY:+ (not removed: -n)}"
  [[ -z $DRY ]] || return 0
  # What a step made as root in its container (an output's work tree a
  # failed step left) is a subordinate user's: removed in podman's user
  # namespace.
  rm -rf "$@" 2>/dev/null && return 0
  for f; do
    host+=("$(host_path "$f")")
  done
  host_podman unshare rm -rf "${host[@]}"
}

# Remove podman images by name; a name another tag shares only goes. One
# a container uses stays, with a warning.
# Inputs:
#   $@      image names
#   DRY     -n
prune_images() {
  local i
  local -a found=()
  for i in "$@"; do
    host_podman image exists "$i" && found+=("$i")
  done
  if ((${#found[@]} == 0)); then
    echo "images: nothing to remove"
    return 0
  fi
  printf '  %s\n' "${found[@]}"
  echo "images: ${#found[@]} to remove${DRY:+ (not removed: -n)}"
  [[ -z $DRY ]] || return 0
  for i in "${found[@]}"; do
    host_podman rmi "$i" >/dev/null || echo "warning: $i stays (in use?)" >&2
  done
}

# The package metas of builds: in each one's prefix, or /pos (as
# ref_metas finds a reference's).
# Inputs:
#   $@      build IDs
#   builds
build_metas() {
  local b d pre f
  for b in "$@"; do
    d=$builds/$b
    pre=$(info_get "$d" prefix)
    for f in "$d"/dest/*"${pre:-/pos}"/lib/pos/packages/*/meta "$d"/dest/*/pos/lib/pos/packages/*/meta; do
      [[ ! -f $f ]] || echo "$f"
    done
  done | sort -u
}

# The prepared and unpacked source trees prune keeps, as <source>/<key>:
# those the kept builds' packages were built from (build-source,
# build-with-source), and those the checkout's HEAD gives (source_id),
# which a run prepares, or ./build prepare did ahead of it, with the
# current build's tools reference.
# Inputs:
#   $@      kept build IDs
#   sources, builds
prune_sources_kept() {
  local s cur
  # shellcheck disable=SC2016
  build_metas "$@" | xargs -r awk '$1 == "build-source" || $1 == "build-with-source" {print $2 "/" $3}'
  cur=$(current_id) || return 0
  TOOLS_REF=$(info_get "$builds/$cur" tools-reference)
  TOOLS_REF=${TOOLS_REF:-none}
  for s in "$sources"/*/; do
    s=${s%/}
    s=${s##*/}
    [[ -n ${SRCPATH[$s]:-} || -n ${ARCHIVE[$s]:-} ]] || continue
    echo "$s/$(source_id "$s" 2>/dev/null | cut -d' ' -f1)"
  done
}

# Remove what the checkout's builds no longer need: the builds but the
# kept ones (prune_keep), their tools images and their outputs' images
# (<tag>:<id>), the tools images of the kept builds but the current one
# (run makes it again), the restored references no kept build names and
# the store does not default to, the source trees no kept build and HEAD
# need (prune_sources_kept), and the cache entries no kept build holds,
# and what an interrupted store left (<key>.tmp). An entry a build holds
# shares its files with the build: removing it would free nothing. Images
# are removed by the IDs of this checkout's builds only: other checkouts
# of the project (the agents') name theirs alike.
# Inputs:
#   [-n]    list what would be removed, remove nothing
#   builds, cache, sources, refs
cmd_prune() {
  local b d k o cur
  local -a gone=() images=() kept=() beside=()
  local -A held=() keep=()
  local -A KEEP=()
  DRY=
  case ${1:-} in
    -n) DRY=1 ;;
    '') ;;
    *) usage ;;
  esac
  cur=$(current_id) || cur=
  prune_keep
  kept=("${!KEEP[@]}")
  echo "keeping builds: $(printf '%s\n' "${kept[@]}" | sort | xargs)${cur:+ (current $cur)}"

  for b in $(prune_builds_all | sort); do
    [[ -z ${KEEP[$b]:-} ]] || continue
    gone+=("$builds/$b")
    for o in "${OUTPUTS[@]}"; do
      [[ -z $(output_meta "$o" tag) ]] || images+=("localhost/$(output_meta "$o" tag):$b")
    done
  done
  for b in $(prune_builds_all); do
    # A build without info (a broken one) is removed, and names no image.
    [[ $b != "$cur" && -f $builds/$b/info ]] || continue
    k=$(info_get "$builds/$b" tools-image)
    [[ -z $k ]] || images+=("$k")
  done
  prune_remove builds "${gone[@]}"
  prune_images "${images[@]}"

  # References: the kept builds' and the store's defaults.
  while read -r k; do
    [[ -z $k ]] || keep[$k]=1
  done < <(for b in "${kept[@]}"; do
             info_get "$builds/$b" toolchain-reference
             info_get "$builds/$b" pos-reference
             info_get "$builds/$b" tools-reference
           done
           for o in toolchain pos extras; do
             reference_default "$o"
           done)
  gone=()
  for d in "$refs"/*/; do
    d=${d%/}
    [[ -n ${keep[${d##*/}]:-} ]] || gone+=("$d")
  done
  prune_remove references "${gone[@]}"

  # Source trees: <source>/<key>, listed, with its .done, .upstream and
  # .epoch, and <key>.tmp, which an interrupted prepare or unpack left.
  keep=()
  while read -r k; do
    keep[$k]=1
  done < <(prune_sources_kept "${kept[@]}")
  gone=()
  for d in "$sources"/*/*; do
    [[ -e $d ]] || continue
    k=${d#"$sources"/}
    for o in .done .upstream .epoch; do
      k=${k%"$o"}
    done
    [[ -z ${keep[${k%.tmp}]:-} || $k == *.tmp ]] || continue
    if [[ $d == "$sources/$k" ]]; then
      gone+=("$d")
    else
      beside+=("$d")
    fi
  done
  prune_remove sources "${gone[@]}"
  [[ -n $DRY ]] || rm -f "${beside[@]}"

  # The cache: entries no kept build holds.
  # shellcheck disable=SC2016
  while read -r k; do
    held[$k]=1
  done < <(build_metas "${kept[@]}" | xargs -r awk '$1 == "build-key" {print $2}')
  gone=()
  for d in "$cache"/*/*/; do
    d=${d%/}
    [[ -d $d ]] || continue
    k=${d##*/}
    [[ $k == *.tmp || -z ${held[$k]:-} ]] && gone+=("$d")
  done
  prune_remove cache "${gone[@]}"
  # Package and source directories left empty.
  [[ -n $DRY ]] || for d in "$cache" "$sources"; do
    [[ ! -d $d ]] || find "$d" -mindepth 1 -maxdepth 1 -type d -empty -delete
  done
}



meta_load
meta_validate || die "invalid package metadata"
outputs_load

cmd=${1:-}
(($#)) && shift
case $cmd in
  plan) cmd_plan "$@" ;;
  run) cmd_run "$@" ;;
  prepare) cmd_prepare "$@" ;;
  rebuild) cmd_rebuild "$@" ;;
  output) cmd_output "$@" ;;
  status) cmd_status ;;
  reference) cmd_reference "$@" ;;
  clean) cmd_clean "$@" ;;
  prune) cmd_prune "$@" ;;
  validate) cmd_validate "$@" ;;
  tag) cmd_tag "$@" ;;
  publish) cmd_publish "$@" ;;
  bump) cmd_bump "$@" ;;
  *) usage ;;
esac
