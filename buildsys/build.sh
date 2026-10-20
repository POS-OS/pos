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
# builds.
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
# (gcc, binutils, the kernel headers) is built by toolchain builds, with
# the toolchain of a toolchain reference, a stored toolchain build
# (work/references/<ref>, restored from the reference store), or Fedora's
# without one, on the glibc of a pos reference, a stored pos build
# (reference.sh). A pos build builds the rest with its toolchain
# reference's toolchain, and assembles the stages with the reference's
# toolchain packages in them. podman runs on the host; from inside a
# toolbox through flatpak-spawn.

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=resolve.sh
source "$base/buildsys/resolve.sh"
# shellcheck source=config.sh
source "$base/buildsys/config.sh"
# shellcheck source=buildinfo.sh
source "$base/buildsys/buildinfo.sh"

builds=$base/work/builds
CHECKS=yes
# Who commits VERSION bumps, as the source syncs are committed.
bot_name=pos-bot bot_email=pos-bot@devzero.dk
sources=$base/work/sources
refs=$base/work/references
# The recipes of the checkout, as git pathspecs: the package directories
# and the stage lists of every tree (resolve.sh).
RECIPES=(':(glob)pos/*/packages/**' ':(glob)pos/*/stage')
fedora_release=$(config fedora-release)
fedora_image=registry.fedoraproject.org/fedora
export LC_ALL=C

# shellcheck source=container.sh
source "$base/buildsys/container.sh"
# shellcheck source=reference.sh
source "$base/buildsys/reference.sh"
# shellcheck source=release.sh
source "$base/buildsys/release.sh"
# shellcheck source=outputs.sh
source "$base/buildsys/outputs.sh"


usage() {
  cat >&2 <<EOF
usage: ./build plan [--new [--toolchain]] [<target>...]
                                               print what run would build, in order
       ./build run [--new [--toolchain] [--source-archives]] [--no-checks] [<target>...]
                                               build the targets, then assemble stage
                                               archives and make the outputs
       ./build prepare [<target>...]           prepare the sources of the targets now
       ./build rebuild <package>...            drop packages from the current build
       ./build output [--no-checks] [<output>...]
                                               make outputs of the current build again
       ./build status                          show the current build
       ./build reference [<id>]                store a toolchain build, or a pos
                                               build's core-libs, as the default
                                               reference of its kind
       ./build clean [<id>]                    remove the tools image of a build
       ./build validate [--unchecked] [<id>]   check that a build is an OS build
       ./build tag [--unchecked]               number the current build: validate it,
                                               tag its commit main-<BUILD>, then bump
       ./build publish [--unchecked]           number the current build as tag does and
                                               copy its artifacts into the release library
       ./build bump                            commit VERSION with the next BUILD

A target is a stage (pos/<stage>/stage) or a package. The default is
every stage. run continues the current build; --new starts another, a
toolchain build with --toolchain. A toolchain build builds the toolchain
packages (meta: pipeline toolchain) and what they need; a pos build
builds the rest, and takes the toolchain from its toolchain reference. An output
(outputs/<output>: images, disks, RPM packages) is made when run
assembles all the stages it requires, after the outputs it requires.
--source-archives makes the new build also write an archive of every
source it built from (pos-src-<source>-<key>.tar.zst) and of the build
recipes (pos-recipes-<stem>.tar.zst).

A new build takes the toolchain from a toolchain reference, a stored
toolchain build, and core-libs from a pos reference, a stored pos build's
core-libs; by default the ones reference marked last, and for a pos build
the pos reference its toolchain was built on. A toolchain build without a
toolchain reference (none) is built by Fedora's compiler; it needs a pos
reference. A pos build without one builds glibc, the first pos reference.
Settings (build.conf.dist) are read from
$build_config; an environment variable overrides one:
  fedora-release  POS_FEDORA_RELEASE  the Fedora release (default 44)
  tools-image     POS_TOOLS_IMAGE     the image tools are installed on
                                      (default $fedora_image:<release>)
  reference-dir   POS_REFERENCE_DIR   the reference store
  toolchain-reference  POS_TOOLCHAIN_REFERENCE  the toolchain reference, or none
  pos-reference   POS_POS_REFERENCE   the pos reference, or none
  release-dir     POS_RELEASE_DIR     the release library publish copies into
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
  printf '\e]2;pos %s\a' "$*" >/dev/tty 2>/dev/null || true
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

# Return 0 if the active pipeline is the toolchain's.
# Inputs:
#   PIPELINE    active pipeline name ("pos" or "toolchain")
is_toolchain_pipeline() {
  [[ ${PIPELINE:-pos} == toolchain ]]
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
# image, write $builds/<id>/info, and point $builds/current at it.
# Writes progress to stderr; the ID is the output.
# Inputs:
#   $1          whether to produce source archives ("yes" or "no")
#   PIPELINE    active pipeline name ("pos" or "toolchain")
build_new() {
  local archives=$1 from branch version
  id=$(date +%Y%m%d%H%M)
  [[ ! -e $builds/$id ]] || die "build $id already exists; wait a minute"
  branch=$(git -C "$base" rev-parse --abbrev-ref HEAD)
  version=$(version_info HEAD "$branch" "$id") || exit 1
  references_choose
  from=$(tools_base)
  bdir=$builds/$id
  mkdir -p "$bdir"/{dest,debug,build,logs}
  tools_build "$from"
  {
    echo "id $id"
    echo "pipeline $PIPELINE"
    echo "fedora $fedora_release"
    echo "tools-base $from"
    echo "tools-image localhost/pos-tools:$id"
    echo "toolchain-reference $TOOLCHAIN_REF"
    echo "pos-reference $POS_REF"
    echo "branch $branch"
    tree_state | awk '{print "commit", $1; print "tree", $2}'
    echo "$version"
    echo "started $(date -u +%FT%TZ)"
    echo "source-archives $archives"
  } >"$builds/$id/info"
  ln -sfn "$id" "$builds/current"
  echo "$id"
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
# instructions. Recorded for the build, each package and each step made,
# so validate can tell that a build was made from one commit.
# Inputs:
#   base    path to the POS checkout
tree_state() {
  local dirty
  dirty=$(git -C "$base" --no-optional-locks status --porcelain --untracked-files=no
          git -C "$base" --no-optional-locks status --porcelain -- VERSION outputs buildsys devtools "${RECIPES[@]}")
  if [[ -n $dirty ]]; then
    echo "$(git -C "$base" rev-parse HEAD) dirty"
  else
    echo "$(git -C "$base" rev-parse HEAD) clean"
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
#   PIPELINE, BUILT[], TOOLCHAIN_REF, POS_REF, REF[], POSREF[], REF_REQ[]
build_load() {
  PIPELINE=$(build_info pipeline)
  PIPELINE=${PIPELINE:-pos}
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
    cat "$base/${PKGDIR[$s]}/prepare.sh" "$base/buildsys/prepare.sh"
    echo "${PREQ[$s]}"
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
  mounts=(net ro:"$base/buildsys" "${RECIPE_MOUNTS[@]}" ro:"$base/${SRCPATH[$s]}" rw:"$dir.tmp" ro:"$dir.upstream")
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
    bash "$hbase/buildsys/prepare.sh" 2>&1 | tee -a "$log"
  mv "$dir.tmp" "$dir"
  touch "$dir.done"
}

# Path to the installed package metadata file that marks a package built.
# Inputs:
#   $1      package name
#   bdir    active build directory
marker() {
  echo "$bdir/dest/$1/pos/lib/pos/packages/$1/meta"
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
# the package, so a /pos tree records what it contains. The meta file is
# written last: its presence marks the package built.
# Inputs:
#   $1      package or output name
#   bdir    active build directory
pkg_record() {
  local p=$1 dest=$bdir/dest/$1 dir extra s
  [[ -d $dest/pos ]] || die "$p: nothing installed into $dest/pos"
  extra=$(find "$dest" -mindepth 1 -maxdepth 1 ! -name pos -print)
  if [[ -n $extra ]]; then
    echo "warning: $p installed paths outside /pos:" >&2
    echo "$extra" >&2
  fi
  # /pos/lib is the only library directory (BUILD.md "Library directory").
  # lib64 comes from build tools that look at the tools image's
  # /usr/lib64 (meson, cmake GNUInstallDirs, Fedora's gcc).
  extra=$(find "$dest/pos" -mindepth 1 -maxdepth 1 \( -name lib64 -o -name lib32 -o -name libx32 \) -print)
  [[ -z $extra ]] || die "$p: installed into $(echo "$extra" | xargs -n1 basename | xargs); set libdir to /pos/lib"
  dir=$dest/pos/lib/pos/packages/$p
  mkdir -p "$dir"
  (cd "$dest" && find pos -mindepth 1 ! -type d ! -path "pos/lib/pos/packages/*" | sed 's|^|/|' | sort) >"$dir/files"
  {
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$base/${PKGDIR[$p]}/meta"
    echo "build $id"
    echo "build-source ${SRC[$(build_of "$p")]} ${SOURCE_ID:-}"
    for s in "${WITH_SOURCE_IDS[@]}"; do
      echo "build-with-source $s"
    done
    echo "build-env ${ENV[*]}"
    echo "build-tools $TOOLS_ID"
    echo "build-toolchain-reference $TOOLCHAIN_REF"
    echo "build-pos-reference $POS_REF"
    echo "built $(date -u +%FT%TZ)"
  } >"$dir/meta.tmp"
  mv "$dir/meta.tmp" "$dir/meta"
  step_made "package-$p"
}

# The staging tree of a package in the environment: this build's, or a
# reference's (<name>@ref, <name>@pos).
# Inputs:
#   $1    environment entry (<pkg>, <pkg>@ref or <pkg>@pos)
#   TOOLCHAIN_REF, POS_REF
env_tree() {
  case $1 in
    *@ref) echo "$refs/$TOOLCHAIN_REF/dest/${1%@ref}/pos" ;;
    *@pos) echo "$refs/$POS_REF/dest/${1%@pos}/pos" ;;
    *) echo "$bdir/dest/$1/pos" ;;
  esac
}

# Compose the /pos of a package build: the trees of the POS packages in
# ENV hard-linked into one directory, which the build container mounts
# read-only. A path has one owner: cp fails on a path another package of
# the environment already put there.
# Inputs:
#   $1     destination root directory ($bdir/roots/$p)
#   ENV    resolved package environment array
root_compose() {
  local root=$1 q
  rm -rf "$root"
  mkdir -p "$root"
  for q in "${ENV[@]}"; do
    case ${KIND[${q%@*}]} in
      package|output)
        cp -al --update=none-fail "$(env_tree "$q")/." "$root/" ||
          die "$p: ${q%@*} ships a path another package of the environment ships" ;;
    esac
  done
}



# The tree a source is built from, and its identity for the package
# metadata and the source archives: the prepared tree's key, or the
# committed tree. Sets SOURCE_DIR and SOURCE_KEY.
# Inputs:
#   $1    source name
# Outputs:
#   SOURCE_DIR, SOURCE_KEY
source_of() {
  local s=$1
  SOURCE_DIR=$base/${SRCPATH[$s]}
  if has_prepare "$s"; then
    prepare_source "$s"
    SOURCE_DIR=$PREPARED
    SOURCE_KEY=$(basename "$PREPARED")
  elif [[ -d $SOURCE_DIR ]]; then
    SOURCE_KEY=$(source_tree "$s")
  else
    SOURCE_KEY=
  fi
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
  env_of "$p" || die "$p: unresolved: ${MISSING[*]}"
  scripts=$(env_scripts | xargs)
  for q in $scripts; do
    env_files+=" ${PKGDIR[$q]}/env.sh"
  done
  log=$bdir/logs/$p.log
  root=$bdir/roots/$p
  local hbase hbdir src_dir s with_dirs=
  hbase=$(host_path "$base")
  hbdir=$(host_path "$bdir")
  for q in "$p" ${OUTS[$p]}; do
    step_start "package-$q"
  done
  source_of "${SRC[$p]}"
  src_dir=$SOURCE_DIR
  SOURCE_ID=$SOURCE_KEY
  # The package's own inputs: the recipes (they source each other's),
  # its source trees, and the build's build, dest and debug directories.
  recipe_mounts
  local -a mounts=(pos:"$root" ro:"$base/buildsys" "${RECIPE_MOUNTS[@]}")
  [[ ! -d $src_dir ]] || mounts+=(ro:"$src_dir")
  WITH_SOURCE_IDS=()
  for s in ${WSRC[$p]}; do
    source_of "$s"
    mounts+=(ro:"$SOURCE_DIR")
    with_dirs+=" $s=$(host_path "$SOURCE_DIR")"
    WITH_SOURCE_IDS+=("$s $SOURCE_KEY")
  done
  mounts+=(rw:"$bdir/build" rw:"$bdir/dest" rw:"$bdir/debug")

  echo "=== $p: setup: ${scripts:-none} ===" | tee "$log"
  echo "env: ${ENV[*]}" | tee -a "$log"
  root_compose "$root"
  step_run "$p" "${mounts[@]}" -- env \
    POS_BASE="$hbase" \
    POS_PACKAGE="$p" \
    POS_RECIPE_DIR="$hbase/${PKGDIR[$p]}" \
    POS_SRC_DIR="$(host_path "$src_dir")" \
    POS_WITH_SRC_DIRS="${with_dirs# }" \
    POS_BUILD_DIR="$hbdir/build/$p" \
    POS_DEST_DIR="$hbdir/dest/$p" \
    POS_DEBUG_DIR="$hbdir/debug/$p" \
    POS_OUTPUTS="${OUTS[$p]# }" \
    POS_ENV_SCRIPTS="${env_files# }" \
    bash "$hbase/buildsys/pkg.sh" 2>&1 | tee -a "$log"
  for q in "$p" ${OUTS[$p]}; do
    pkg_record "$q"
    BUILT[$q]=1
  done
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
#   $@    [--new] [--toolchain] [<stage>|<package>...]
cmd_plan() {
  local id= bdir n=0 t toolchain=
  local -a args=()
  for t in "$@"; do
    case $t in
      --new) id="<new>" ;;
      --toolchain) toolchain=1 ;;
      -*) usage ;;
      *) args+=("$t") ;;
    esac
  done
  [[ -z $toolchain || -n $id ]] || die "--toolchain is chosen when a build is created; use it with --new"
  if [[ -z $id ]] && id=$(current_id); then
    bdir=$builds/$id
    build_load
  else
    id="<new>"
    PIPELINE=${toolchain:+toolchain}
    PIPELINE=${PIPELINE:-pos}
    references_choose
    load_references
  fi
  ((${#args[@]})) || mapfile -t args < <(pipeline_targets)
  bootstrap_check "${args[@]}"
  targets_expand "${args[@]}"
  is_toolchain_pipeline || targets_check "${TARGETS[@]}"
  echo "build $id ($PIPELINE)"
  echo "toolchain reference $TOOLCHAIN_REF (${#REF[@]} packages), pos reference $POS_REF (${#POSREF[@]} packages)"
  while next_package "${TARGETS[@]}"; do
    env_of "$NEXT"
    printf '%3d %-24s setup: %s\n' $((++n)) "$NEXT" "$(env_scripts | xargs)"
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
# Inputs:
#   bdir, PKGS, KIND, BUILT
source_archives() {
  local p s key out commit
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
  commit=$(git -C "$base" rev-parse HEAD)
  if [[ $commit != "$(build_info commit)" ]] ||
     [[ -n $(git -C "$base" status --porcelain --untracked-files=no -- outputs buildsys "${RECIPES[@]}") ]]; then
    echo "warning: outputs, buildsys, recipes or stages differ from the commit the build started at;" \
         "the recipes archive holds HEAD" >&2
  fi
  out=$bdir/pos-recipes-$(build_stem "$bdir").tar.zst
  git -C "$base" archive --format=tar --prefix="pos-recipes-$(build_stem "$bdir")/" HEAD \
    outputs buildsys "${RECIPES[@]}" BUILD.md README.md | zstd -q -f -o "$out.tmp"
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
    "$base/buildsys/assemble.sh" "$bdir" "$t" "$refs/$TOOLCHAIN_REF"
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
#   $@    [--new] [--toolchain] [--source-archives] [--no-checks] [<stage>|<package>...]
cmd_run() {
  local new= archives=no t toolchain= all=
  local -a args=()
  for t in "$@"; do
    case $t in
      --new) new=1 ;;
      --toolchain) toolchain=1 ;;
      --source-archives) archives=yes ;;
      --no-checks) CHECKS=no ;;
      -*) usage ;;
      *) args+=("$t") ;;
    esac
  done
  if [[ $archives == yes && -z $new ]]; then
    die "--source-archives is chosen when a build is created; use it with --new"
  fi
  [[ -z $toolchain || -n $new ]] || die "--toolchain is chosen when a build is created; use it with --new"
  if [[ -n $new ]] || ! id=$(current_id); then
    PIPELINE=${toolchain:+toolchain}
    PIPELINE=${PIPELINE:-pos}
    id=$(build_new "$archives")
    echo "new build $id"
  fi
  bdir=$builds/$id
  [[ -n $(build_info tools-image) ]] ||
    die "build $id builds in toolboxes, which this buildsys no longer does; start another with run --new"
  build_versioned "$bdir"
  build_load
  echo "build $id ($PIPELINE), toolchain reference $TOOLCHAIN_REF (${#REF[@]} packages)," \
       "pos reference $POS_REF (${#POSREF[@]} packages)"
  if ((${#args[@]} == 0)); then
    all=1
    mapfile -t args < <(pipeline_targets)
  fi
  bootstrap_check "${args[@]}"
  targets_expand "${args[@]}"
  is_toolchain_pipeline || targets_check "${TARGETS[@]}"
  tools_ensure
  TOOLS_ID=$(host_podman image inspect --format '{{.Id}}' "$(build_info tools-image)")

  title_init
  build_os "${args[@]}"
  local -a outputs
  mapfile -t outputs < <(outputs_of "${STAGES_BUILT[@]}")
  outputs_run "${outputs[@]}"
  [[ -z $all ]] || step_made complete
}

# Prepare the sources the targets are built from, ahead of a run (run
# prepares them when it needs them). Uses the current build's tools image.
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
      [[ -z ${seen[$s]:-} ]] && has_prepare "$s" || continue
      seen[$s]=1
      prepare_source "$s"
      echo "$s: $PREPARED"
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
    for q in "$p" ${OUTS[$p]}; do
      rm -rf "${bdir:?}/dest/$q" "${bdir:?}/debug/$q" "${bdir:?}/made/package-$q"
      echo "$q: dropped from build $id"
    done
  done
  # What was made from the packages is made again by run.
  find "$bdir/made" -mindepth 1 -maxdepth 1 ! -name 'package-*' -delete 2>/dev/null || true
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
  if host_podman image exists "localhost/pos-tools:$id"; then
    echo "removing image localhost/pos-tools:$id"
    host_podman rmi "localhost/pos-tools:$id" >/dev/null
  fi
  rm -rf "${builds:?}/$id/roots"
  echo "outputs are kept in $builds/$id"
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
  validate) cmd_validate "$@" ;;
  tag) cmd_tag "$@" ;;
  publish) cmd_publish "$@" ;;
  bump) cmd_bump "$@" ;;
  *) usage ;;
esac
