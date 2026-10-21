# Sourced by _pkg_setup for builds where gcc is installed.
#
# It searches /pos only. glibc and gcc's target libraries use it too: glibc
# overrides the part of its search that would be circular (it passes
# -nostdinc and -nostdlib); the target libraries are built by the new
# xgcc, not by this CC.
export CC=${sdk_prefix}/bin/gcc
export CXX=${sdk_prefix}/bin/g++
export LD=${sdk_prefix}/bin/ld

# A toolchain reference from before the sdk prefix has gcc and binutils in
# /pos/bin, its gcc naming /pos/bin/as and ld. In a toolchain build on one,
# binutils is the build's, in /pos/sdk/bin, where COMPILER_PATH points that
# gcc. Only then: Fedora's gcc, for programs run in the build, would take
# as and ld from it too.
if [[ ! -x $CC ]]; then
  export CC=${prefix}/bin/gcc CXX=${prefix}/bin/g++
  if [[ -x $LD ]]; then
    export COMPILER_PATH=${sdk_prefix}/bin
  else
    export LD=${prefix}/bin/ld
  fi
fi
