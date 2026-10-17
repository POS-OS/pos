#!/usr/bin/env bash
# Release and version management: validation, tagging, and version bumping.
# Sourced by buildsys/build.sh. BUILD.md "Build numbers".

# The BUILD number in VERSION at a commit, or nothing; version_update the
# same for UPDATE, which only a release line has.
# Inputs:
#   $1    git revision (e.g. HEAD or commit hash)
version_build() {
  { git -C "$base" show "$1:VERSION" 2>/dev/null || true; } | sed -n 's/^BUILD=\([0-9][0-9]*\)$/\1/p'
}

# The UPDATE number in VERSION at a commit, or nothing.
# Inputs:
#   $1    git revision (e.g. HEAD or commit hash)
version_update() {
  { git -C "$base" show "$1:VERSION" 2>/dev/null || true; } | sed -n 's/^UPDATE=\([0-9][0-9]*\)$/\1/p'
}

# The info lines naming a build made at a commit (buildinfo.sh): its BUILD,
# UPDATE and version, <BUILD> or <BUILD>u<UPDATE>. None without VERSION.
# Inputs:
#   $1    git revision (e.g. HEAD or commit hash)
version_info() {
  local n u
  n=$(version_build "$1")
  u=$(version_update "$1")
  [[ -n $n ]] || return 0
  echo "build-number $n"
  [[ -z $u ]] || echo "update $u"
  echo "version $n${u:+u$u}"
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

# Number the current build: tag its commit main-<BUILD>, with the build ID
# in the tag, then bump. HEAD is on main and has not been bumped since the
# build's commit, so the next BUILD follows this one.
# Inputs:
#   $@    [--unchecked]
cmd_tag() {
  local unchecked=no commit
  [[ ${1:-} != --unchecked ]] || { unchecked=yes; shift; }
  (($# == 0)) || usage
  [[ $(git -C "$base" symbolic-ref --short HEAD 2>/dev/null) == main ]] || die "tag numbers builds of main; check out main"
  # The tagger is whoever numbers the build: git's identity here.
  git -C "$base" var GIT_COMMITTER_IDENT >/dev/null 2>&1 ||
    die "git has no identity for the tagger; set user.name and user.email (git config)"
  id=$(current_id) || die "no current build"
  validate "$unchecked"
  commit=$(build_info commit)
  git -C "$base" merge-base --is-ancestor "$commit" HEAD || die "build $id: $commit is not on main"
  [[ $(version_build HEAD) == "$BUILD_NUMBER" ]] ||
    die "VERSION at HEAD is BUILD $(version_build HEAD), build $id is BUILD $BUILD_NUMBER; bumped since?"
  git -C "$base" tag -a "main-$BUILD_NUMBER" -m "POS BUILD $BUILD_NUMBER

build $id
reference $(build_info reference)
$(checks_said)" "$commit"
  echo "tagged $commit main-$BUILD_NUMBER"
  cmd_bump
}

# Commit VERSION with the next BUILD. tag runs it after tagging; run it
# alone when tag failed after the tag was made.
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
