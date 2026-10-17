# The /pos tree of the sdk stage, next to pos of the same build.
output() {
  rpm_stages pos-sdk "The POS SDK, installed in /pos" "POS build $id: the compiler, binutils, kernel headers and developer
tools of the sdk stage, installed in /pos next to pos." assemble pos "Requires: pos = $evr"
  rpm_stages pos-sdk-debuginfo "Debug info for pos-sdk" "The debug info split off the programs and libraries of pos-sdk, build
$id, in /pos/lib/debug/.build-id, where gdb and debuginfod find it by build ID." \
    assemble-debug pos/lib/debug "Requires: pos-sdk = $evr"
}
