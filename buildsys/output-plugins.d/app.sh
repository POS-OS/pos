#!/usr/bin/env bash
# App archives for outputs (buildsys/outputs.sh): the prefix of a toolchain
# or extras build, /apps/<name>/<version>, as one tree with its manifest,
# which pos-app installs. BUILD.md "App archives".

# The version a package's record names (its meta), in a tree of package
# trees: in the prefix, or in /pos for a package that installs there
# (meta prefix /pos).
# Inputs:
#   $1    directory of package trees (<build>/dest)
#   $2    the prefix of its packages
#   $3    package name
# Outputs:
#   the version on stdout; exits when the package has no record or version
_app_record_version() {
  local m v
  for m in "$1/$3$2/lib/pos/packages/$3/meta" "$1/$3/pos/lib/pos/packages/$3/meta"; do
    [[ -f $m ]] || continue
    v=$(awk '$1 == "version" {print $2}' "$m")
    [[ -n $v ]] || die "$output: $m records no version"
    echo "$v"
    return 0
  done
  die "$output: no package $3 in $1"
}

# The version of a package this build built.
# Inputs:
#   $1    package name
#   bdir
app_version() {
  _app_record_version "$bdir/dest" "$(info_get "$bdir" prefix)" "$1"
}

# The directory of one of the build's references, restored in
# work/references (outputs see it read-only).
# Inputs:
#   $1    the reference: toolchain, pos or tools (the info's
#         <kind>-reference)
#   bdir, base
# Outputs:
#   the directory on stdout; exits when the build has none or it is not
#   restored
_app_ref_dir() {
  local ref dir
  ref=$(info_get "$bdir" "$1-reference")
  [[ -n $ref && $ref != none ]] || die "$output: build $id has no $1 reference"
  dir=$base/work/references/$ref
  [[ -f $dir/info ]] || die "$output: $1 reference $ref is not restored in work/references; run the build again"
  echo "$dir"
}

# The version of a package one of the build's references built.
# Inputs:
#   $1    the reference: toolchain, pos or tools
#   $2    package name
app_ref_version() {
  local dir
  dir=$(_app_ref_dir "$1") || exit 1
  _app_record_version "$dir/dest" "$(info_get "$dir" prefix)" "$2"
}

# A key of the info of one of the build's references (product-version:
# the pos release line of the pos reference).
# Inputs:
#   $1    the reference: toolchain, pos or tools
#   $2    info key
app_ref_info() {
  local dir v
  dir=$(_app_ref_dir "$1") || exit 1
  v=$(info_get "$dir" "$2")
  [[ -n $v ]] || die "$output: the $1 reference's info has no $2"
  echo "$v"
}

# Make the build's app archive, <name>-app-<stem>.tar.zst: the trees of
# every package it built merged at its prefix, /apps/<name>/<version>,
# archived from inside, with the manifest ./app (pos-app). Packages that
# install in /pos (gcc-runtime) are pos's, and debug info stays out. The
# manifest is also written beside the archive, <name>-app-<stem>.app, to
# read before downloading it. Every file is root's.
# Inputs:
#   $@    the manifest's lines after name, version, id and release: path
#         and requires lines (pos-app)
#   bdir, id, stem, work
app_make() {
  local prefix name version tree d n=0 out
  prefix=$(info_get "$bdir" prefix)
  [[ $prefix =~ ^/apps/([^/]+)/([^/]+)$ ]] ||
    die "$output: the build's prefix is $prefix, not /apps/<name>/<version>"
  name=${BASH_REMATCH[1]}
  version=${BASH_REMATCH[2]}
  tree=$work/tree
  mkdir -p "$tree"
  for d in "$bdir"/dest/*; do
    [[ -d $d$prefix ]] || continue
    cp -a --reflink=auto "$d$prefix/." "$tree/"
    n=$((n + 1))
  done
  ((n)) || die "$output: build $id has no package in $prefix"
  {
    echo "name $name"
    echo "version $version"
    echo "id $id"
    echo "release $stem"
    printf '%s\n' "$@"
  } >"$tree/app"
  out=$bdir/$name-app-$stem
  cp "$tree/app" "$out.app"
  tar --zstd --owner=0 --group=0 --numeric-owner -cf "$out.tar.zst" -C "$tree" .
  echo "$out.tar.zst: $n packages"
}
