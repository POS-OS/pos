# Kernel UAPI headers. glibc's installed headers include <linux/errno.h> and
# <asm/*.h>, and the compiler searches only /pos/include, so these must live
# in the prefix. src/linux is the subset of the kernel tree that
# headers_install needs. It builds out of tree (O=): the only compiled
# program is the build's own fixdep helper, made with Fedora's compiler.

pkg() {
  # No compiler environment is required; kbuild does not read the CFLAGS
  # _pkg_setup exports.

  make -C "$src_dir" O="$build_dir" ARCH=x86_64 \
       INSTALL_HDR_PATH="${dest_dir}${prefix}" headers_install
}
