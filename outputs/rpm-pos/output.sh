# The OS as one package. It installs nothing outside /pos and provides
# nothing Fedora packages require, so it installs on any Fedora system.
output() {
  rpm_stages pos "POS, installed in /pos" "POS build $id: the stages ${stages[*]}, installed in /pos.
Nothing outside /pos; pos-fedora makes it the base of a Fedora system." assemble pos
  rpm_stages pos-debuginfo "Debug info for pos" "The debug info split off the programs and libraries of pos, build $id,
in /pos/lib/debug/.build-id, where gdb and debuginfod find it by build ID." \
    assemble-debug pos/lib/debug "Requires: pos = $evr"
}
