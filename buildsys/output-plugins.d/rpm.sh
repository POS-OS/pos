#!/usr/bin/env bash
# RPM packages of a build for outputs (buildsys/outputs.sh), made from the
# output's assembled stages. The functions run in output(), in a build
# container. Each package is written to <bdir>/rpm, as
# <name>-<evr>.x86_64.rpm; dnf installs them as files. Its spec is
# $work/<name>.spec. BUILD.md "RPM packages".

# Print sorted unique "<type> <path>" entries (d directory, f file, l
# symlink) of the output's stages in a tree of assembled stages.
# Inputs:
#   $1    tree directory under bdir (assemble, assemble-debug)
#   $2    path below each stage's tree to list (pos, pos/lib/debug)
#   stages, bdir
rpm_paths() {
  local s
  for s in "${stages[@]}"; do
    [[ -d $bdir/$1/$s/$2 ]] || continue
    (cd "$bdir/$1/$s" && find "$2" -printf '%y /%p\n')
  done | sort -u -k2,2
}

# The %files list of paths (rpm_paths): directories as %dir.
# Inputs:
#   $1    file of "<type> <path>" lines
rpm_files() {
  echo '%defattr(-,root,root,-)'
  awk '$1 == "d" {print $2}' "$1" | rpm_escape | sed 's|^|%dir |'
  awk '$1 != "d" {print $2}' "$1" | rpm_escape
}

# rpm expands macros and globs in a file list and splits it at spaces.
# Inputs:
#   stdin    list of file paths, one per line
rpm_escape() {
  sed -e 's/%/%%/g' -e 's/[][*?{}\\" ]/\\&/g'
}

# The header every spec shares. rpmbuild's defaults are for Fedora's /usr:
# automatic dependencies would make pos provide the sonames of Fedora's
# libraries (libc.so.6()(64bit)) and take Fedora's place without
# pos-fedora. The post-install steps strip, split debug info, add
# /usr/lib/.build-id links outside /pos, compress man pages and rewrite
# shebangs. POS ships its tree as built.
# Inputs:
#   $1      RPM package Name
#   $2      RPM package Summary
#   ${@:3}  further spec header lines (Requires: ...)
#   evr
rpm_spec_head() {
  cat <<EOF
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none
%global _binary_payload w3T0.zstdio

Name: $1
Version: ${evr%%-*}
Release: ${evr#*-}
Summary: $2
License: NOASSERTION
AutoReqProv: no
EOF
  printf '%s\n' "${@:3}"
}

# Build a binary RPM from $work/<name>.spec into <bdir>/rpm, replacing the
# build's earlier one.
# Inputs:
#   $1    RPM package name
#   bdir, evr, work
rpm_build() {
  local name=$1
  echo "rpm: $name"
  mkdir -p "$bdir/rpm"
  rm -f "$bdir/rpm/$name-$evr.x86_64.rpm"
  rpmbuild -bb --target x86_64 \
    --define "_topdir $work/rpmbuild" \
    --define "_rpmdir $bdir/rpm" \
    --define "_build_name_fmt %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm" \
    "$work/$name.spec" >"$work/$name.log" 2>&1 || {
    tail -n 20 "$work/$name.log" >&2
    die "rpmbuild failed: $name"
  }
  rm -rf "$work/rpmbuild"
}

# A package of the output's stages from a tree of assembled stages, merged
# in the order given, as an image does. It owns every path below the given
# directory, directories included, so removing the package removes them;
# directories two packages own stay while either is installed. Modes come
# from the trees, with group write removed as in images (fs_stages);
# set-uid bits are kept. Nothing is made when the stages have nothing
# there (debug info of builds before pkg_strip).
# Inputs:
#   $1      RPM package name
#   $2      RPM Summary
#   $3      RPM %description
#   $4      tree directory under bdir (assemble, assemble-debug)
#   $5      directory the package owns, below the tree (pos, pos/lib/debug)
#   ${@:6}  further spec header lines (Requires: pos = <evr>)
#   stages, bdir, work
rpm_stages() {
  local name=$1 summary=$2 desc=$3 tree=$4 owned=$5 s
  shift 5
  rpm_paths "$tree" "$owned" >"$work/$name.paths"
  if [[ ! -s $work/$name.paths ]]; then
    echo "rpm: $name: nothing in /$owned"
    return 0
  fi
  rpm_files "$work/$name.paths" >"$work/$name.files"
  {
    rpm_spec_head "$name" "$summary" "$@"
    cat <<EOF

%description
$desc

%install
mkdir -p %{buildroot}/pos
$(for s in "${stages[@]}"; do
  [[ ! -d $bdir/$tree/$s/pos ]] || echo "cp -a '$bdir/$tree/$s/pos/.' %{buildroot}/pos/"
done)
find %{buildroot} ! -type l -perm -g=w ! -perm -1000 -exec chmod g-w {} +

%files -f $work/$name.files
EOF
  } >"$work/$name.spec"
  rpm_build "$name"
}
