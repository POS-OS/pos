#!/usr/bin/env bash
# Container runtime and tools image management. Sourced by buildsys/build.sh.
#
# Manages running build steps inside isolated tools containers via podman.
# Transparently handles host podman invocation when running inside a toolbox
# via flatpak-spawn.

# Return 0 if running inside a Fedora toolbox container.
in_toolbox() {
  [[ -f /run/.toolboxenv ]]
}

# Paths as the host sees them, for podman.
# Inputs:
#   $1    path inside the current environment (strips /run/host inside a toolbox)
host_path() {
  if in_toolbox && [[ $1 == /run/host/* ]]; then
    echo "${1#/run/host}"
  else
    echo "$1"
  fi
}

# podman of the host. From inside a toolbox it is reached the way the
# toolbox CLI reaches itself, through flatpak-spawn; podman nested in the
# toolbox container is not used.
# Inputs:
#   $@    podman subcommand and arguments
host_podman() {
  if in_toolbox; then
    flatpak-spawn --host podman "$@"
  else
    podman "$@"
  fi
}

# The Fedora packages of the tools image: the host-requires and
# prepare-requires of every package and the host-requires of every output
# (outputs.sh), so any step of the run finds what it declares.
# Inputs:
#   PKGS, HREQ, PREQ, OUT_HREQ
tools_packages() {
  local p
  {
    for p in "${PKGS[@]}"; do
      echo ${HREQ[$p]} ${PREQ[$p]}
    done
    echo "${OUT_HREQ[@]}"
  } | xargs -n1 | sort -u
}

# Make the build's tools image, localhost/pos-tools:<id>, from the pinned
# base (info: tools-base), and record its packages in tools-packages.
# Inputs:
#   $1      pinned base image reference (from tools_base)
#   id      build ID
#   bdir    active build directory
tools_build() {
  local from=$1 log=$bdir/logs/tools.log
  tools_packages >"$bdir/tools-packages.tmp"
  echo "=== tools image localhost/pos-tools:$id from $from ===" | tee "$log" >&2
  host_podman build --build-arg "BASE=$from" \
    --build-arg "PACKAGES=$(xargs <"$bdir/tools-packages.tmp")" \
    --label "pos.build=$id" -t "localhost/pos-tools:$id" \
    -f "$(host_path "$base/buildsys/tools.containerfile")" "$(host_path "$base/buildsys")" 2>&1 |
    tee -a "$log" >&2
  mv "$bdir/tools-packages.tmp" "$bdir/tools-packages"
}

# The base of a new build's tools image, pulled now and pinned by digest,
# so the build keeps it when the tag moves on.
# Inputs:
#   fedora_image, fedora_release, config(tools-image)
tools_base() {
  local from pinned
  from=$(config tools-image)
  from=${from:-$fedora_image:$fedora_release}
  [[ $from == localhost/* ]] || host_podman pull -q "$from" >/dev/null
  pinned=$(host_podman image inspect --format '{{index .RepoDigests 0}}' "$from" 2>/dev/null) || pinned=
  [[ -n $pinned && $pinned != "<no value>" ]] ||
    pinned=$(host_podman image inspect --format '{{.Id}}' "$from") || die "no image $from"
  echo "$pinned"
}

# The tools image has the host-requires of every package as they were when
# it was made. It is made again, on the same base, when a package now
# declares more, or when it was removed (clean).
# Inputs:
#   id, bdir
tools_ensure() {
  local missing
  missing=$(tools_packages | comm -13 "$bdir/tools-packages" - | xargs)
  if [[ -n $missing ]]; then
    echo "tools image: adding $missing" >&2
  elif host_podman image exists "localhost/pos-tools:$id"; then
    return 0
  fi
  tools_build "$(build_info tools-base)"
}

# Run a step of the build in a container of its tools image. The step sees
# the image and what it is given: ro:<path> and rw:<path> mount a path at
# its host path, read-only or read-write, and pos:<path> mounts a composed
# root as /pos, read-only. The user is the caller and there is no network,
# unless given net (network) or root: the container's root, which is the
# caller outside it, allowed to mount in the container's own namespaces
# (SYS_ADMIN of rootless podman covers its user namespace only).
# Its output goes to the caller only, not to podman's log (journald by
# default on Fedora).
# Inputs:
#   $1              container name suffix (pos-$id-$name)
#   <mount|opt>...  zero or more of: net, root, ro:<path>, rw:<path>, pos:<path>
#   --              separator before command
#   $@              command and arguments to execute inside the tools container
step_run() {
  local name=$1 a h net=--network=none user=--userns=keep-id
  local -a mounts=()
  shift
  while [[ $1 != -- ]]; do
    a=$1
    shift
    h=$(host_path "${a#*:}")
    case $a in
      net) net= ;;
      root) user=--cap-add=SYS_ADMIN ;;
      ro:*) mounts+=(-v "$h:$h:ro") ;;
      rw:*) mounts+=(-v "$h:$h") ;;
      pos:*) mounts+=(-v "$h:/pos:ro") ;;
      *) die "step_run: unknown argument $a" ;;
    esac
  done
  shift
  host_podman run --rm --replace --log-driver=none --name "pos-$id-$name" ${net:+"$net"} ${user:+"$user"} \
    --security-opt label=disable --pids-limit=-1 --ulimit=host \
    "${mounts[@]}" -w /tmp -e HOME=/tmp -e LC_ALL=C \
    "$(build_info tools-image)" "$@"
}
