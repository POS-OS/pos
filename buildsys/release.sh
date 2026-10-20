#!/usr/bin/env bash
# Release and version management: validation, tagging, publishing and
# version bumping. Sourced by buildsys/build.sh. BUILD.md "Build numbers".

# The value of a field of VERSION at a commit, or nothing. VERSION is read
# as data, never sourced.
# Inputs:
#   $1    git revision (e.g. HEAD or commit hash)
#   $2    field (BUILD, PRODUCT_VERSION, PRODUCT_RELEASE, REVISION, RPM_RELEASE)
version_field() {
  { git -C "$base" show "$1:VERSION" 2>/dev/null || true; } | sed -n "s/^$2=//p" | tail -n 1
}

# The BUILD number in VERSION at a commit, or nothing.
# Inputs:
#   $1    git revision (e.g. HEAD or commit hash)
version_build() {
  version_field "$1" BUILD | sed -n '/^[0-9][0-9]*$/p'
}

# The info lines of the version of a build made at a commit: the fields of
# VERSION, checked, and its product release, the static one of VERSION or
# <branch>.<timestamp>, the build ID as 20261017-1524. A branch name keeps
# only what rpm allows in a release (letters, digits and . _ + ~ ^); the
# rest becomes _. Exits when a field is missing or malformed.
# Inputs:
#   $1    git revision (e.g. HEAD or commit hash)
#   $2    branch the build is made on
#   $3    build ID
version_info() {
  local rev=$1 branch=$2 id=$3 pv rel r rpmrel n type=stable
  local num='^[0-9]+$' chars='^[A-Za-z0-9._+~^]+$'
  pv=$(version_field "$rev" PRODUCT_VERSION)
  rel=$(version_field "$rev" PRODUCT_RELEASE)
  r=$(version_field "$rev" REVISION)
  rpmrel=$(version_field "$rev" RPM_RELEASE)
  n=$(version_field "$rev" BUILD)
  [[ $pv =~ ^[0-9]+\.[0-9]+$ ]] || die "VERSION at $rev: PRODUCT_VERSION is <major>.<minor>, not '$pv'"
  [[ $n =~ $num ]] || die "VERSION at $rev: BUILD is a number, not '$n'"
  [[ $r =~ $num ]] || die "VERSION at $rev: REVISION is a number, not '$r'"
  [[ $rpmrel =~ $num ]] || die "VERSION at $rev: RPM_RELEASE is a number, not '$rpmrel'"
  if [[ -z $rel ]]; then
    type=development
    rel=$(printf '%s' "$branch" | tr -c 'A-Za-z0-9._+~^' _).${id:0:8}-${id:8}
  elif [[ ! $rel =~ $chars ]]; then
    die "VERSION at $rev: PRODUCT_RELEASE has only letters, digits and . _ + ~ ^, not '$rel'"
  fi
  echo "product-version $pv"
  echo "product-release $rel"
  echo "release-type $type"
  echo "build-number $n"
  echo "revision $r"
  echo "rpm-release $rpmrel"
}

# Check that build id is an OS build (BUILD.md "Build numbers"): a pos
# build with a complete run, whose every record (step_made) was made from
# its commit, clean, with its checks unless unchecked is yes; its BUILD
# (VERSION at that commit) above every main-* tag. Lists every problem and
# exits, or sets BUILD_NUMBER and UNCHECKED (the records made unchecked).
# Inputs:
#   $1    whether to accept unchecked steps ("yes" or "no")
#   id    build ID to validate
# Outputs:
#   BUILD_NUMBER, UNCHECKED[]
validate() {
  local unchecked=$1 commit f r last
  local -a problems=()
  bdir=$builds/$id
  [[ -f $bdir/info ]] || die "no build $id"
  commit=$(build_info commit)
  UNCHECKED=()
  [[ $(build_info pipeline) == pos ]] || problems+=("not a pos build")
  [[ -f $bdir/made/complete ]] || problems+=("no complete run since it was created or last rebuilt")
  for f in "$bdir"/made/*; do
    [[ -f $f ]] || continue
    r=$(<"$f")
    case $r in
      "$commit clean") ;;
      "$commit clean unchecked")
        UNCHECKED+=("$(basename "$f")")
        [[ $unchecked == yes ]] || problems+=("$(basename "$f"): made without its checks (--unchecked accepts it)") ;;
      *) problems+=("$(basename "$f"): made from $r, not $commit clean") ;;
    esac
  done
  BUILD_NUMBER=$(version_build "$commit")
  if [[ -z $BUILD_NUMBER ]]; then
    problems+=("no BUILD in VERSION at $commit")
  else
    last=$(git -C "$base" tag -l 'main-*' | sed -n 's/^main-\([0-9][0-9]*\)$/\1/p' | sort -n | tail -1)
    ((BUILD_NUMBER > ${last:-0})) || problems+=("BUILD $BUILD_NUMBER is not above the last tag, main-$last")
  fi
  if ((${#problems[@]})); then
    echo "build $id is not an OS build:" >&2
    printf '  %s\n' "${problems[@]}" >&2
    exit 1
  fi
}

# The checks of a validated build, for messages and the tag.
# Inputs:
#   UNCHECKED    array populated by validate()
checks_said() {
  if ((${#UNCHECKED[@]})); then
    echo "checks skipped: ${UNCHECKED[*]}"
  else
    echo "checks passed"
  fi
}

# CLI command: validate that a build is a clean, complete OS release build.
# Inputs:
#   $@    [--unchecked] [<build-id>]
cmd_validate() {
  local unchecked=no
  [[ ${1:-} != --unchecked ]] || { unchecked=yes; shift; }
  (($# <= 1)) || usage
  id=${1:-$(current_id)} || die "no current build"
  validate "$unchecked"
  echo "build $id is BUILD $BUILD_NUMBER (commit $(build_info commit), $(checks_said))"
}

# Check that the current build can be numbered: validate it, with HEAD on
# main and not bumped since the build's commit, so the next BUILD follows
# this one, and git's identity set for the tagger, whoever numbers the
# build. Lists the problems of validate and exits, or sets what validate
# sets.
# Inputs:
#   $1    whether to accept unchecked steps ("yes" or "no")
# Outputs:
#   id, bdir, BUILD_NUMBER, UNCHECKED[]
tag_check() {
  local commit
  [[ $(git -C "$base" symbolic-ref --short HEAD 2>/dev/null) == main ]] || die "tag numbers builds of main; check out main"
  git -C "$base" var GIT_COMMITTER_IDENT >/dev/null 2>&1 ||
    die "git has no identity for the tagger; set user.name and user.email (git config)"
  id=$(current_id) || die "no current build"
  validate "$1"
  commit=$(build_info commit)
  git -C "$base" merge-base --is-ancestor "$commit" HEAD || die "build $id: $commit is not on main"
  [[ $(version_build HEAD) == "$BUILD_NUMBER" ]] ||
    die "VERSION at HEAD is BUILD $(version_build HEAD), build $id is BUILD $BUILD_NUMBER; bumped since?"
}

# Tag the build's commit main-<BUILD>, an annotated tag with the build's
# ID, identifier, references and checks.
# Inputs:
#   id, bdir, BUILD_NUMBER, UNCHECKED (tag_check)
tag_make() {
  local commit
  commit=$(build_info commit)
  git -C "$base" tag -a "main-$BUILD_NUMBER" -m "POS BUILD $BUILD_NUMBER

build $id
version $(build_identifier "$bdir")
toolchain-reference $(build_info toolchain-reference)
pos-reference $(build_info pos-reference)
$(checks_said)" "$commit"
  echo "tagged $commit main-$BUILD_NUMBER"
}

# Number the current build: tag its commit, then bump.
# Inputs:
#   $@    [--unchecked]
cmd_tag() {
  local unchecked=no
  [[ ${1:-} != --unchecked ]] || { unchecked=yes; shift; }
  (($# == 0)) || usage
  tag_check "$unchecked"
  tag_make
  cmd_bump
}

# Check that the release library takes the current build's release: not
# there yet, and no release of the same product version in it with an
# RPM version-release that is the same or a higher rpm release number, so
# its RPM packages update the earlier ones.
# Inputs:
#   $1      the release library (release-dir)
#   bdir
publish_check() {
  local store=$1 name info pv rr evr
  name=$(build_stem "$bdir")
  pv=$(info_get "$bdir" product-version)
  rr=$(info_get "$bdir" rpm-release)
  evr=$(rpm_evr "$bdir")
  [[ ! -e $store/$name ]] || die "release $name is in $store already"
  for info in "$store"/*/info; do
    [[ -f $info ]] || continue
    [[ $(info_get "${info%/info}" product-version) == "$pv" ]] || continue
    [[ $(rpm_evr "${info%/info}") != "$evr" ]] ||
      die "release $(basename "${info%/info}") in $store has the RPM version-release $evr too; raise RPM_RELEASE in VERSION"
    (($(info_get "${info%/info}" rpm-release) <= rr)) ||
      die "release $(basename "${info%/info}") in $store has a higher RPM_RELEASE than $rr for $pv; raise it in VERSION"
  done
}

# Copy the build's artifacts into a release directory: its info, what is
# named after the build (pos-*-<stem>.*: stage and debug archives, image
# archives and their package lists, disks, the recipes archive), its
# source archives and its RPM packages in rpm/, and SHA256SUMS of them.
# Inputs:
#   $1      the release directory to fill
#   bdir
publish_copy() {
  local dir=$1 stem f
  stem=$(build_stem "$bdir")
  mkdir -p "$dir/rpm"
  cp "$bdir/info" "$dir/info"
  for f in "$bdir"/pos-*-"$stem".* "$bdir"/pos-src-*.tar.zst; do
    [[ ! -f $f ]] || cp --reflink=auto "$f" "$dir/"
  done
  for f in "$bdir"/rpm/*.rpm; do
    [[ ! -f $f ]] || cp --reflink=auto "$f" "$dir/rpm/"
  done
  (cd "$dir" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum >SHA256SUMS)
}

# Publish the current build: number it as tag does, and copy its
# artifacts into the release library, <release-dir>/<release>, named as
# the artifacts are (build_stem). The release is filled under a temporary
# name and appears when the tag is made; then VERSION is bumped.
# Inputs:
#   $@    [--unchecked]
cmd_publish() {
  local unchecked=no store name
  [[ ${1:-} != --unchecked ]] || { unchecked=yes; shift; }
  (($# == 0)) || usage
  store=$(config release-dir)
  [[ -n $store ]] || die "release-dir is not set (POS_RELEASE_DIR; build.conf.dist)"
  [[ -d $store ]] || die "release-dir $store is not a directory"
  tag_check "$unchecked"
  publish_check "$store"
  name=$(build_stem "$bdir")
  rm -rf "${store:?}/.$name.tmp"
  publish_copy "$store/.$name.tmp"
  tag_make
  mv "$store/.$name.tmp" "$store/$name"
  echo "published $store/$name"
  cmd_bump
}

# Commit VERSION with the next BUILD. tag and publish run it after tagging;
# run it alone when they failed after the tag was made.
# Inputs:
#   none ($# must be 0)
cmd_bump() {
  local n
  (($# == 0)) || usage
  git -C "$base" diff --quiet HEAD -- VERSION || die "VERSION has uncommitted changes"
  n=$(version_build HEAD)
  [[ -n $n ]] || die "no BUILD in VERSION at HEAD"
  sed -i "s/^BUILD=$n\$/BUILD=$((n + 1))/" "$base/VERSION"
  GIT_COMMITTER_NAME=$bot_name GIT_COMMITTER_EMAIL=$bot_email \
    git -C "$base" commit -q --author="$bot_name <$bot_email>" -m "BUILD $((n + 1)) is next" -- VERSION
  echo "VERSION: BUILD $((n + 1))"
}
