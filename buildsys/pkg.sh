#!/usr/bin/env bash
# Package build runner and helpers for build.sh recipes.
#
# buildsys/build.sh runs this script in a build container. The builder
# resolves the package's requirements, composes exactly that set as the
# container's /pos, and the build's prefix where it is another (read-only),
# and passes the result in the environment.
# Of the checkout, the container has the recipes (buildsys, the package
# directories pos/<tree>/packages), the package's source tree, and the
# build's build, dest and debug directories. Each package's build.sh
# defines a pkg() phase function called between _pkg_setup and _pkg_finish.
#
#   POS_BASE        the POS checkout
#   POS_PACKAGE     the package being built
#   POS_RECIPE_DIR  its package directory, with build.sh
#   POS_PREFIX      the prefix the package installs in: /pos, or the
#                   project's (/apps/pos-extras/<version>)
#   POS_SRC_DIR     its source tree (pos/<tree>/src/<source>, or prepared)
#   POS_WITH_SRC_DIRS  further source trees (meta "with-sources"), as
#                   <source>=<dir> words; pkg_sync_src copies each into
#                   the build tree
#   POS_BUILD_DIR   scratch build directory
#   POS_DEST_DIR    staging directory; the package installs into
#                   $POS_DEST_DIR$POS_PREFIX
#   POS_OUTPUTS     further packages this build produces (meta "outputs");
#                   the recipe installs each into $(pkg_output <name>)
#   POS_OUTPUT_PREFIXES  the prefix of each output, as <output>=<prefix>
#                   words: POS_PREFIX, or /pos for one whose meta says so
#   POS_SDK_PREFIX  the prefix of the sdk the build compiles with, its
#                   toolchain reference's (/apps/pos-sdk/<version>, /pos/sdk
#                   for toolchains from before prefixes); a pos-sdk build
#                   installs the new one in its own prefix
#   POS_TOOLS_PREFIX  the prefix of the build tools from an extras
#                   reference (/apps/pos-extras/<version>-<release>), or
#                   empty for fedora's, in the tools image (BUILD.md
#                   "Build tools"); the build-tools profile's env.sh puts
#                   them on PATH
#   POS_LINKABLE    the packages of the environment the package may link:
#                   its own environment, not what only the build tools
#                   brought; _pkg_linkcheck checks its ELF files
#   POS_DEBUG_DIR   where _pkg_finish puts the package's separate debug
#                   info, $POS_DEBUG_DIR$POS_PREFIX/lib/debug; an output's goes
#                   next to it, as with the staging directories
#   SOURCE_DATE_EPOCH  the time of the package's source, for the dates
#                   tools write, as in man pages
#   POS_ENV_SCRIPTS the env.sh files of the packages in the resolved
#                   environment that set up the build: a recipe's, or the
#                   one a reference's package installed, in /pos;
#                   _pkg_setup sources each.
#                   The compiler comes from the package providing gcc (the
#                   toolchain reference's gcc, or gcc-host, Fedora's, without
#                   one); linking against /pos from the pos-link
#                   profile.
set -euo pipefail

package=${POS_PACKAGE:?run recipes through buildsys/build.sh}

# A bootstrap package can source the main recipe after setting these. They
# are appended to the main recipe's configure arguments, where a later flag
# wins over an earlier one.
if ! declare -p configure_extra &>/dev/null; then
  configure_extra=()
fi

# Recipes run in a build container (buildsys/build.sh: build_container),
# not on the host or in a toolbox.
_require_container() {
  if [[ ! -f /run/.containerenv || -f /run/.toolboxenv ]]; then
    echo "build scripts must run in a build container (./build)" >&2
    exit 1
  fi
}

# Initialize the package build environment and directory layout before pkg() runs.
# Inputs (environment):
#   POS_BASE, POS_PACKAGE, POS_RECIPE_DIR, POS_PREFIX, POS_SRC_DIR,
#   POS_BUILD_DIR, POS_DEST_DIR, POS_DEBUG_DIR, POS_OUTPUTS, POS_ENV_SCRIPTS,
#   POS_SDK_PREFIX, POS_TOOLS_PREFIX
# Outputs (shell variables set for pkg()):
#   base, recipe_dir, src_dir, build_dir, dest_dir, debug_dir, prefix (the
#   build's: /pos, or /apps/pos-extras/<version>), pos_prefix (/pos),
#   sdk_prefix (the compiler's sdk), tools_prefix (the build tools', or
#   empty), sysconfdir (/etc), localstatedir (/var), nproc,
#   CFLAGS, CXXFLAGS, LDFLAGS
_pkg_setup() {
  _require_container
  base=${POS_BASE:?}
  recipe_dir=${POS_RECIPE_DIR:?}
  src_dir=${POS_SRC_DIR:?}
  build_dir=${POS_BUILD_DIR:?}
  dest_dir=${POS_DEST_DIR:?}
  prefix=${POS_PREFIX:?}
  # The OS, which every build links against, whatever its own prefix.
  pos_prefix=/pos
  # The sdk (the toolchain) the build compiles with, in its own prefix
  # (BUILD.md "Prefix").
  sdk_prefix=${POS_SDK_PREFIX:-${pos_prefix}/sdk}
  # The build tools of an extras reference, in their own prefix.
  tools_prefix=${POS_TOOLS_PREFIX:-}
  # Configuration is read from the machine's /etc, never from inside the
  # prefix. Variable data is /var. Files a package installs under either
  # are shipped defaults; _pkg_finish moves them to /pos/share/factory
  # (the systemd-tmpfiles factory tree).
  sysconfdir=/etc
  localstatedir=/var
  nproc=$(nproc)

  if [[ ! -d $src_dir ]]; then
    echo "missing sources: $src_dir" >&2
    exit 1
  fi

  debug_dir=${POS_DEBUG_DIR:?}
  rm -rf "$build_dir" "$dest_dir" "$debug_dir"
  mkdir -p "$build_dir" "$dest_dir"
  cd "$build_dir" || exit 1
  local o
  for o in ${POS_OUTPUTS:-}; do
    rm -rf "$(pkg_output "$o")" "$(dirname "$debug_dir")/${o:?}"
    mkdir -p "$(pkg_output "$o")"
  done

  _pkg_flags

  local f
  for f in ${POS_ENV_SCRIPTS:-}; do
    # shellcheck source=/dev/null
    source "$f"
  done
}

# Compiler and linker flags every package is built with (BUILD.md "Build
# flags"): optimized with debug info, which _pkg_finish splits off, and the
# hardening Fedora and Arch build with. -fPIE and -fstack-protector-strong
# are the POS compiler's defaults (pos-sdk's gcc recipe). env.sh files add
# to these; recipes whose own build sets flags (glibc, gcc) replace them
# with pos_optflags.
# Inputs: pos_optflags
# Outputs (exported): CFLAGS, CXXFLAGS, LDFLAGS
pos_optflags="-O2 -g -pipe"
_pkg_flags() {
  local harden="-fexceptions -Wp,-D_FORTIFY_SOURCE=3 -fstack-clash-protection -fcf-protection"
  harden+=" -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
  export CFLAGS="$pos_optflags $harden"
  export CXXFLAGS="$pos_optflags $harden -Wp,-D_GLIBCXX_ASSERTIONS"
  export LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,--build-id=sha1"
}

# Print the staging directory path of a declared secondary output package.
# Inputs:
#   $1          output package name (must be listed in POS_OUTPUTS)
#   dest_dir    main package staging directory
pkg_output() {
  if [[ " ${POS_OUTPUTS:-} " != *" $1 "* ]]; then
    echo "${package}: $1 is not an output of this package" >&2
    exit 1
  fi
  echo "$(dirname "$dest_dir")/$1"
}

# The prefix an output installs in: the build's, or /pos (meta prefix), as
# pos-sdk's gcc-runtime does.
# Inputs:
#   $1    output name
#   POS_OUTPUT_PREFIXES, prefix
pkg_output_prefix() {
  local w
  for w in ${POS_OUTPUT_PREFIXES:-}; do
    [[ ${w%%=*} != "$1" ]] || { echo "${w#*=}"; return; }
  done
  echo "$prefix"
}

# Copy the source into the build tree, and each further source into a
# directory of it named after the source, replacing what was there.
# Inputs:
#   src_dir            primary source tree
#   build_dir          scratch build directory
#   POS_WITH_SRC_DIRS  optional space-separated <source>=<dir> pairs
pkg_sync_src() {
  local w
  find "$build_dir" -mindepth 1 -delete
  cp -a "$src_dir/." "$build_dir/"
  for w in ${POS_WITH_SRC_DIRS:-}; do
    rm -rf "${build_dir:?}/${w%%=*}"
    cp -a "${w#*=}" "$build_dir/${w%%=*}"
  done
}

# Run configure in the current working directory with standard POS paths.
# If the first argument is a path to a configure script (e.g. "$src_dir/configure"
# or ../configure for out-of-tree builds), that script is invoked directly;
# otherwise ./configure is used (syncing sources into $build_dir first if
# ./configure is not already present in the current directory).
# Inputs:
#   [$1]               optional path to configure script (matching */configure)
#   $@                 extra arguments passed to configure
#   configure_extra    optional array of override flags appended after $@
pkg_configure() {
  local script=./configure
  if [[ ${1:-} == */configure ]]; then
    script=$1
    shift
  elif [[ ! -x ./configure ]]; then
    pkg_sync_src
  fi
  local -a args=(
    --prefix="$prefix"
    --libdir="${prefix}/lib"
    --sysconfdir="$sysconfdir"
    --localstatedir="$localstatedir"
    "$@"
  )
  [[ ${#configure_extra[@]} -eq 0 ]] || args+=("${configure_extra[@]}")
  "$script" "${args[@]}"
}

# Compile in the current working directory using parallel make.
# Inputs:
#   $@       extra arguments passed to make
#   nproc    parallel job count
pkg_compile() {
  make -j"$nproc" "$@"
}

# Install from the current working directory into $dest_dir via make install.
# Inputs:
#   $@          extra arguments passed to make install
#   dest_dir    staging directory passed as DESTDIR
pkg_install() {
  make DESTDIR="$dest_dir" install "$@"
}

# Standard Autotools lifecycle: configure, compile, and install into $dest_dir.
# Inputs:
#   $@    extra arguments passed to pkg_configure
pkg_autotools() {
  pkg_configure "$@"
  pkg_compile
  pkg_install
}

# Standard CMake lifecycle: configure out-of-source, build with -j, install with DESTDIR.
# Inputs:
#   $@    extra arguments passed to cmake configuration
pkg_cmake() {
  cmake -S "$src_dir" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=None \
        -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_INSTALL_SYSCONFDIR="$sysconfdir" \
        -DCMAKE_INSTALL_LOCALSTATEDIR="$localstatedir" \
        "$@"
  cmake --build "$build_dir" -j "$nproc"
  DESTDIR="$dest_dir" cmake --install "$build_dir"
}

# Standard Meson lifecycle: configure out-of-source, compile with -j, install with DESTDIR.
# Inputs:
#   $@    extra arguments passed to meson setup
pkg_meson() {
  meson setup "$build_dir" "$src_dir" \
        --prefix="$prefix" \
        --libdir=lib \
        --sysconfdir="$sysconfdir" \
        --localstatedir="$localstatedir" \
        --buildtype=plain \
        "$@"
  meson compile -C "$build_dir" -j "$nproc"
  DESTDIR="$dest_dir" meson install -C "$build_dir"
}

# The linker flags of C programs (LDFLAGS: the POS loader, /pos/lib, the
# hardening and build ID flags) as rustc arguments, for cargo builds.
# Inputs:
#   LDFLAGS
# Outputs:
#   the arguments, one -C link-arg=<flag> per flag, on stdout
_pkg_rust_link_args() {
  local f
  for f in $LDFLAGS; do
    printf -- '-C link-arg=%s ' "$f"
  done
}

# Build a Rust package with cargo, offline, from the crates its prepare
# recipe vendored (prep_cargo_vendor in buildsys/prepare.sh). The compiler
# is the build host's (host-requires rust cargo); programs link with the
# environment's gcc against /pos, as C programs do, and keep their debug
# info for _pkg_finish to split off. Build scripts and proc-macros run in
# the build, proc-macros inside rustc, so they link with the host's cc
# against the tools image's glibc: an explicit --target keeps RUSTFLAGS,
# and the POS linker in them, to the target's crates (host-requires gcc
# for the host's cc). The programs are in $cargo_out; the recipe installs
# them.
# Inputs:
#   $@    extra arguments passed to cargo build
#   build_dir, nproc, CFLAGS, LDFLAGS
# Outputs:
#   cargo_out   directory of the built programs
pkg_cargo() {
  pkg_sync_src
  export CARGO_HOME=$build_dir/.cargo-home CARGO_TARGET_DIR=$build_dir/target
  export CARGO_PROFILE_RELEASE_DEBUG=true CARGO_PROFILE_RELEASE_STRIP=false
  export RUSTFLAGS="-C linker=${CC:-gcc} $(_pkg_rust_link_args)"
  local triple
  triple=$(rustc -vV | sed -n 's/^host: //p')
  cargo build --release --offline --locked -j "$nproc" --target "$triple" "$@"
  cargo_out=$CARGO_TARGET_DIR/$triple/release
}

# Environment for Go builds: Go modules from the source's committed
# vendor directory, no network and no other Go toolchain than the build
# host's (host-requires golang). cgo compiles with CFLAGS and links with
# the environment's gcc and LDFLAGS (the POS loader, /pos/lib): external
# linking, which programs that use cgo get, and which -linkmode=external
# asks for where a recipe passes its own -ldflags.
# Inputs:
#   build_dir, CFLAGS, LDFLAGS
# Outputs (exported):
#   GOPATH, GOCACHE, GOFLAGS, GOTOOLCHAIN, GOPROXY, CGO_ENABLED, CGO_CFLAGS,
#   CGO_LDFLAGS
pkg_go_env() {
  export GOPATH=$build_dir/.gopath GOCACHE=$build_dir/.gocache
  export GOFLAGS="-mod=vendor -trimpath -ldflags=-linkmode=external"
  export GOTOOLCHAIN=local GOPROXY=off
  export CGO_ENABLED=1 CGO_CFLAGS=$CFLAGS CGO_LDFLAGS=$LDFLAGS
}

# Mark programs that must run set-uid root. The staging tree is written by an
# unprivileged user, so ownership is applied when the archive is extracted as
# root (assemble.sh records owner 0:0); only the mode bit is set here.
# Inputs:
#   $@          installed paths relative to $dest_dir (e.g. "${prefix}/bin/su")
#   dest_dir    staging directory
pkg_setuid() {
  local f
  for f in "$@"; do
    if [[ ! -f ${dest_dir}${f} ]]; then
      echo "${package}: setuid target missing: ${f}" >&2
      exit 1
    fi
    chmod 4755 "${dest_dir}${f}"
  done
}

# Remove the scratch build directory ($build_dir).
# Inputs:
#   build_dir    scratch build directory
_pkg_cleanup() {
  rm -rf "$build_dir"
}

# Move shipped /etc and /var files into the factory tree. Reject anything a
# package tried to put in ${prefix}/etc or ${prefix}/var. A tmpfiles.d file
# of the package (factory-<package>.conf) copies each into place where it
# is missing (C lines), at boot and when an image is made. A path one of
# the package's own tmpfiles.d lines already creates (systemd's
# 20-systemd-*.conf, credstore.conf) gets no line: tmpfiles would read both
# and warn about the duplicate. Lines that only adjust a path (z, a, h)
# leave it in.
# Inputs:
#   [$1]    staging directory to process (defaults to $dest_dir)
_pkg_factory() {
  local dest=${1:-$dest_dir} kind f path
  local factory=${dest}${prefix}/share/factory
  local conf=${dest}${prefix}/lib/tmpfiles.d/factory-$(basename "$dest").conf
  local -A named=()
  rm -f "$conf"
  for kind in etc var; do
    if [[ -d ${dest}${prefix}/${kind} ]]; then
      echo "${package}: installed into ${prefix}/${kind}; use ${kind} outside the prefix" >&2
      exit 1
    fi
    if [[ -d ${dest}/${kind} ]]; then
      mkdir -p "$factory"
      rm -rf "${factory:?}/${kind}"
      mv "${dest}/${kind}" "${factory}/${kind}"
    fi
  done
  [[ -d $factory ]] || return 0
  mkdir -p "$(dirname "$conf")"
  for f in "$(dirname "$conf")"/*.conf; do
    [[ -f $f ]] || continue
    while read -r type path _; do
      [[ ${type//[^[:alpha:]]/} != [fFdDvqQpLcbC] ]] || named[$path]=1
    done < <(grep -v -E '^[[:space:]]*(#|$)' "$f")
  done
  # Files and links are copied; an empty directory (sudoers.d) is made
  # with its mode, as the factory tree loses it with the empty ones. Group
  # write is dropped unless sticky, as outputs do (output-plugins.d: fs.sh,
  # rpm.sh).
  (cd "$factory" && find . \( -type f -o -type l \) -printf '%P\n' | sort) |
    while read -r f; do
      [[ -z ${named[/$f]:-} ]] || continue
      echo "C /$f - - - - ${prefix}/share/factory/$f"
    done >"$conf"
  (cd "$factory" && find . -mindepth 1 -type d -empty -printf '%m %P\n' | sort -k2) |
    while read -r m f; do
      [[ -z ${named[/$f]:-} ]] || continue
      ((8#$m & 01000)) || m=$(printf '%o' $((8#$m & ~020)))
      echo "d /$f $m - - -"
    done >>"$conf"
  [[ -s $conf ]] || rm -f "$conf"
}

# A file belongs to one package: what an output holds is removed from the
# main package, so a recipe can install everything and then install the
# output's part again into the output.
# Inputs:
#   dest_dir       main package staging directory
#   POS_OUTPUTS    space-separated list of secondary output package names
_pkg_split() {
  local o out f
  for o in ${POS_OUTPUTS:-}; do
    out=$(pkg_output "$o")
    _pkg_factory "$out"
    (cd "$out" && find . ! -type d -print0) |
      while IFS= read -r -d '' f; do
        rm -f "${dest_dir}/${f#./}"
      done
  done
  find "$dest_dir" -mindepth 1 -depth -type d -empty -delete
}

# Give the ELF programs and libraries of a staging tree outside /pos the
# runpath to the libraries of their own prefix they link, relative to
# themselves ($ORIGIN/../lib from bin), so a program loads the libraries
# of the tree it comes from, wherever the tree is (BUILD.md "Prefix").
# The POS loader's cache covers /pos/lib only. The directories looked in
# are <prefix>/lib and the runpath entries in the prefix a build tool set
# (libtool's absolute libdir); a needed library is found in this build's
# staging trees or the build environment's prefix (other packages of the
# project). Entries outside the prefix (build directories) are dropped.
# /pos keeps no runpath at all. Uses patchelf (a project's pos-link
# host-requires it).
# Inputs:
#   $1    staging directory to scan ($dest_dir or output staging dir)
#   [$2]  the tree's prefix (default $prefix)
#   prefix, pos_prefix, dest_dir, POS_OUTPUTS
_pkg_runpath() {
  local dest=$1 prefix=${2:-$prefix} f o d s t old new mode id
  local -a trees=("$dest_dir") needed=() dirs=() entries=()
  local -A seen=()
  [[ $prefix != "$pos_prefix" && -d $dest$prefix ]] || return 0
  for o in ${POS_OUTPUTS:-}; do
    trees+=("$(pkg_output "$o")")
  done
  # The build environment's own tree, mounted read-only.
  trees+=("")
  while IFS= read -r -d '' f; do
    [[ $(head -c 4 "$f" | od -An -c | tr -d ' \n') == 177ELF ]] || continue
    id=$(stat -c %d:%i "$f")
    [[ -z ${seen[$id]:-} ]] || continue
    seen[$id]=1
    mapfile -t needed < <(readelf -d "$f" 2>/dev/null | awk -F'[][]' '/\(NEEDED\)/ {print $2}')
    ((${#needed[@]})) || continue
    old=$(readelf -d "$f" 2>/dev/null | awk -F'[][]' '/\((RUNPATH|RPATH)\)/ {print $2}')
    dirs=("$prefix/lib")
    entries=()
    for d in ${old//:/ }; do
      case $d in
        '$ORIGIN'*) entries+=("$d") ;;
        "$prefix" | "$prefix"/*) [[ " ${dirs[*]} " == *" $d "* ]] || dirs+=("$d") ;;
      esac
    done
    for d in "${dirs[@]}"; do
      for s in "${needed[@]}"; do
        for t in "${trees[@]}"; do
          [[ -e $t$d/$s ]] || continue
          d=$(realpath -m -s --relative-to="$(dirname "${f#"$dest"}")" "$d")
          [[ $d == . ]] && entries+=('$ORIGIN') || entries+=("\$ORIGIN/$d")
          continue 3
        done
      done
    done
    new=$(IFS=:; echo "${entries[*]}")
    [[ $new != "$old" ]] || continue
    command -v patchelf >/dev/null ||
      { echo "${package}: no patchelf to set runpaths with (host-base, or build-tools, has none)" >&2; exit 1; }
    mode=$(stat -c %a "$f")
    chmod u+w "$f"
    if [[ -n $new ]]; then
      patchelf --set-rpath "$new" "$f"
    else
      patchelf --remove-rpath "$f"
    fi
    chmod "$mode" "$f"
    echo "${package}: runpath ${f#"$dest"}: ${old:-none} -> ${new:-none}"
  done < <(find "$dest" \( -path "$dest${prefix}/include" -o -path "$dest${prefix}/share" \) -prune -o -type f -print0)
}

# Check that the ELF files of a staging tree link only libraries of the
# packages they may (POS_LINKABLE): its own environment's, not those only
# the build tools brought into /pos, which a configure script can find
# without the package requiring them (BUILD.md "Build tools"). A library
# is looked up where the loader finds it, the tree's own lib, its prefix
# and /pos/lib, and its package by the files record of each package in
# the environment (<prefix>/lib/pos/packages/<name>/files). One the
# package installs itself, or none records, is not checked.
# Inputs:
#   $1    staging directory to scan ($dest_dir or output staging dir)
#   [$2]  the tree's prefix (default $prefix)
#   POS_LINKABLE, pos_prefix, package
_pkg_linkcheck() {
  local dest=$1 pre=${2:-$prefix} f s d owner bad=
  local -A owners=() ok=() seen=()
  [[ -n ${POS_TOOLS_PREFIX:-} ]] || return 0
  for s in ${POS_LINKABLE:-}; do
    ok[$s]=1
  done
  for f in "$pos_prefix"/lib/pos/packages/*/files "$pre"/lib/pos/packages/*/files; do
    [[ -f $f ]] || continue
    owner=$(basename "$(dirname "$f")")
    while read -r d; do
      owners[$d]=$owner
    done < <(grep -E "^($pos_prefix|$pre)/lib/[^/]+\.so[.0-9]*\$" "$f")
  done
  while IFS= read -r -d '' f; do
    [[ $(head -c 4 "$f" | od -An -c | tr -d ' \n') == 177ELF ]] || continue
    for s in $(readelf -d "$f" 2>/dev/null | awk -F'[][]' '/\(NEEDED\)/ {print $2}'); do
      [[ -z ${seen[$s]:-} ]] || continue
      seen[$s]=1
      [[ ! -e $dest$pre/lib/$s ]] || continue
      for d in "$pre/lib/$s" "$pos_prefix/lib/$s"; do
        [[ -e $d ]] || continue
        owner=${owners[$d]:-}
        if [[ -n $owner && -z ${ok[$owner]:-} ]]; then
          echo "${package}: ${f#"$dest"} links $s of $owner, which only the build tools brought; require $owner, or keep it from being found" >&2
          bad=1
        fi
        break
      done
    done
  done < <(find "$dest" \( -path "$dest${pre}/include" -o -path "$dest${pre}/share" \) -prune -o -type f -print0)
  [[ -z $bad ]]
}

# Split the debug info off the ELF programs and libraries of a staging
# tree and strip them, as Fedora's debuginfo packages do. The debug info
# goes to <debug><prefix>/lib/debug/.build-id/<xx>/<rest>.debug, where gdb and
# debuginfod look it up by build ID. The loader keeps its symbol table
# (valgrind needs it) and static libraries lose only their debug info.
# strip writes archives deterministically (-D: members with zero dates and
# owners), whichever binutils it is; the tools image's, Fedora's, writes
# the current date otherwise.
# Object files (crt*.o) are left as they are.
# Inputs:
#   $1    staging directory to scan ($dest_dir or output staging dir)
#   $2    debuginfo destination directory ($debug_dir or output debug dir)
#   [$3]  the tree's prefix (default $prefix)
_pkg_strip() {
  local dest=$1 debug=$2 pre=${3:-$prefix} f magic type id dbg mode
  local -A seen=()
  while IFS= read -r -d '' f; do
    # ELF, or an ar archive. A .a can also be a linker script (glibc's
    # libm.a), which is text.
    magic=$(head -c 8 "$f" | od -An -c | tr -d ' \n')
    [[ $magic == 177ELF* || $magic == '!<arch>\n' ]] || continue
    id=$(stat -c %d:%i "$f")
    [[ -z ${seen[$id]:-} ]] || continue
    seen[$id]=1
    mode=$(stat -c %a "$f")
    chmod u+w "$f"
    if [[ $magic == '!<arch>\n' ]]; then
      strip -g -D "$f"
    else
      type=$(readelf -h "$f" 2>/dev/null | awk '$1 == "Type:" {print $2}')
      if [[ $type == EXEC || $type == DYN ]]; then
        id=$(readelf -n "$f" 2>/dev/null | awk '$1 == "Build" && $2 == "ID:" {print $3}')
        if [[ -n $id ]]; then
          dbg=$debug${pre}/lib/debug/.build-id/${id:0:2}/${id:2}.debug
          if [[ ! -e $dbg ]]; then
            mkdir -p "$(dirname "$dbg")"
            objcopy --only-keep-debug "$f" "$dbg"
            chmod 0644 "$dbg"
          fi
        else
          echo "${package}: no build ID, debug info dropped: ${f#"$dest"}" >&2
        fi
        case $f in
          */ld-linux-*.so.*) strip -g "$f" ;;
          *.so | *.so.*) strip --strip-unneeded "$f" ;;
          *) strip --strip-all "$f" ;;
        esac
      fi
    fi
    chmod "$mode" "$f"
  done < <(find "$dest" \( -path "$dest${pre}/include" -o -path "$dest${pre}/share" \) -prune -o -type f -print0)
}

# Finalize the package staging tree(s) after pkg() completes: relocate /etc and
# /var defaults to factory, split secondary outputs, set runpaths outside
# /pos, strip ELF binaries into separate debuginfo, and clean up the build
# directory.
# Inputs:
#   dest_dir, debug_dir, build_dir, POS_OUTPUTS
_pkg_finish() {
  local o
  _pkg_factory
  _pkg_split
  _pkg_runpath "$dest_dir"
  _pkg_linkcheck "$dest_dir"
  _pkg_strip "$dest_dir" "$debug_dir"
  for o in ${POS_OUTPUTS:-}; do
    _pkg_runpath "$(pkg_output "$o")" "$(pkg_output_prefix "$o")"
    _pkg_linkcheck "$(pkg_output "$o")" "$(pkg_output_prefix "$o")"
    _pkg_strip "$(pkg_output "$o")" "$(dirname "$debug_dir")/$o" "$(pkg_output_prefix "$o")"
  done
  _pkg_cleanup
}

_pkg_setup
# shellcheck source=/dev/null
source "$recipe_dir/build.sh"
declare -F pkg >/dev/null || { echo "${package}: build.sh must define pkg()" >&2; exit 1; }
cd "$build_dir"
pkg
_pkg_finish
