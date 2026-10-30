# autoreconf generates the build system. Not autogen.sh: it runs the same
# tools after checking the automake version against those upstream tested.
#
# The version comes from git log or, in a release tarball, from
# util/dist-version.sh (make dist: getversion.sh -s), which the drive
# database's version line needs, with a revision count since 7.5. The
# prepared tree has no git, so the file is written here as make dist
# would: by getversion.sh, against the upstream history at the upstream
# commit (commits and trees only, no file contents).

prep() {
  local git_dir=$prep_dir/.version-git commit
  commit=$(prep_upstream commit)
  # Before autoreconf, which can replace tracked files (getversion.sh would
  # call the tree modified).
  git clone -q --bare --filter=blob:none "$(prep_upstream url)" "$git_dir"
  GIT_DIR=$git_dir GIT_WORK_TREE=$prep_dir git reset -q "$commit"
  GIT_DIR=$git_dir GIT_WORK_TREE=$prep_dir util/getversion.sh -s >util/dist-version.sh.tmp
  rm -rf "$git_dir"
  mv util/dist-version.sh.tmp util/dist-version.sh
  autoreconf -fi
  grep -q "^SMARTMONTOOLS_GIT_REV='${commit:0:12}'" util/dist-version.sh &&
    grep -q '^SMARTMONTOOLS_GIT_SVN_REV=[0-9]' util/dist-version.sh || {
    echo "smartmontools: util/dist-version.sh without the upstream revision" >&2
    cat util/dist-version.sh >&2
    exit 1
  }
}
