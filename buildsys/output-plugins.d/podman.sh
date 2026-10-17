#!/usr/bin/env bash
# Outputs in the host's podman (buildsys/outputs.sh). The functions run in
# output_host(). An output's name in podman is its meta tag, its PATH by
# its path-priority: pos for POS's own layout, host for Fedora layouts,
# which link most of /pos/bin into /usr/bin. BUILD.md "Images made with
# podman".

# Import an output's archive (fs_archive) into podman as <tag>:<id>.
# Inputs:
#   $1      output name
#   id, bdir
podman_import() {
  local o=$1 path=/usr/local/bin:/usr/bin:/pos/bin:/pos/sbin
  [[ $(output_meta "$o" path-priority) != pos ]] || path=/pos/bin:/pos/sbin:/usr/local/bin:/usr/bin
  host_podman import --change "ENV PATH=$path" --change 'CMD ["/usr/bin/bash"]' \
    --change "LABEL pos.build=$id" --change "LABEL pos.version=$(build_identifier "$bdir")" \
    "$(host_path "$(output_file tar.zst "$o")")" "$(output_meta "$o" tag):$id"
}

# Make the output's image with podman from its containerfile, on top of
# another output's image (BASE), imported for it. It is tagged with the
# build ID and with its product version, which moves to the build that
# made the image last (toolboxes are made from <tag>:<product version>).
# Inputs:
#   $1      the output it is made from
#   id, bdir, output
podman_build() {
  local from=$1 name version
  version=$(info_get "$bdir" product-version)
  podman_import "$from"
  name=localhost/$(output_meta "$output" tag)
  host_podman build --build-arg "BASE=localhost/$(output_meta "$from" tag):$id" \
    --label "pos.build=$id" --label "pos.version=$(build_identifier "$bdir")" -t "$name:$id" \
    -f "$(host_path "$(output_dir)/containerfile")" "$(host_path "$(output_dir)")"
  echo "$name:$id"
  host_podman tag "$name:$id" "$name:$version"
  echo "$name:$version"
}
