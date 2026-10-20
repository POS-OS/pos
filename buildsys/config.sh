#!/usr/bin/env bash
# Build settings, sourced by buildsys/build.sh and devtools.
#
# A setting is its environment variable when set, else its line in the
# build configuration, else its default. The configuration is
# ${POS_BUILD_CONFIG:-~/.config/pos/build.conf}, made from build.conf.dist:
# "<key> <value>" lines and # comments. It is read as data, never sourced.
# Only new builds read settings; a build records what it uses in its info.

build_config=${POS_BUILD_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/pos/build.conf}

# The settings: key, environment variable, default.
config_keys=(
  "fedora-release POS_FEDORA_RELEASE 44"
  "tools-image POS_TOOLS_IMAGE -"
  "reference-dir POS_REFERENCE_DIR -"
  "toolchain-reference POS_TOOLCHAIN_REFERENCE -"
  "pos-reference POS_POS_REFERENCE -"
  "release-dir POS_RELEASE_DIR -"
)

declare -A CONFIG=()

# Load key/value settings from $build_config into CONFIG[].
# Inputs:
#   build_config        path to configuration file
#   POS_BUILD_CONFIG    optional explicit config path override
# Outputs:
#   CONFIG              associative array of configured settings
config_load() {
  local key value line known k
  if [[ ! -f $build_config ]]; then
    [[ -z ${POS_BUILD_CONFIG:-} ]] || {
      echo "POS_BUILD_CONFIG: no such file: $build_config" >&2
      exit 1
    }
    return 0
  fi
  while read -r key value; do
    known=
    for line in "${config_keys[@]}"; do
      read -r k _ <<<"$line"
      [[ $k == "$key" ]] && known=1
    done
    if [[ $key == reference ]]; then
      echo "$build_config: the setting reference is now toolchain-reference" >&2
      exit 1
    elif [[ -z $known ]]; then
      echo "$build_config: unknown setting: $key" >&2
      exit 1
    fi
    CONFIG[$key]=$value
  done < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$build_config")
}

# The value of a setting; empty for one without a default.
# Inputs:
#   $1    setting key (fedora-release, tools-image, reference-dir,
#         toolchain-reference, pos-reference, release-dir)
config() {
  local line k var def
  for line in "${config_keys[@]}"; do
    read -r k var def <<<"$line"
    [[ $k == "$1" ]] || continue
    [[ $def != - ]] || def=
    if [[ -n ${!var:-} ]]; then
      echo "${!var}"
    else
      echo "${CONFIG[$k]:-$def}"
    fi
    return 0
  done
  echo "config: unknown setting: $1" >&2
  exit 1
}

config_load
if [[ -n ${POS_REFERENCE:-} ]]; then
  echo "POS_REFERENCE is now POS_TOOLCHAIN_REFERENCE" >&2
  exit 1
fi
