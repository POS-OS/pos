# Assembler and linker for the sdk compiler. gcc execs as and ld; without
# these the sdk gcc would call the build container's /usr/bin tools, whose
# ld searches /usr/lib64 on its own. --with-lib-path makes this ld
# search /pos/lib only, which closes the last route by which host libraries
# reach a POS binary.

pkg() {
  # Out-of-tree, as binutils requires. No debuginfod: binutils cannot require
  # elfutils, which is built with the gcc that execs it; auto would link it
  # wherever elfutils happens to be in /pos. The bundled zlib and no zstd,
  # as for gcc: the toolchain runs on glibc only (BUILD.md "Toolchain").
  # In the sdk prefix, whose lib the loader does not search: libbfd,
  # libopcodes, libctf and libsframe are linked in statically. ar and
  # ranlib write archive members with zero dates and owners and mode 0644
  # (their D option): two builds of a package then give the same archives.
  pkg_configure "${src_dir}/configure" \
    --prefix="$sdk_prefix" \
    --libdir="${sdk_prefix}/lib" \
    --with-lib-path="${prefix}/lib" \
    --disable-shared \
    --enable-ld=default \
    --enable-plugins \
    --enable-64-bit-bfd \
    --enable-new-dtags \
    --enable-deterministic-archives \
    --enable-relro \
    --enable-default-hash-style=gnu \
    --without-zstd \
    --without-debuginfod \
    --disable-gprofng \
    --disable-werror \
    --disable-nls
  # tooldir is where binutils puts the tools for a compiler of the target
  # (<prefix>/<target>/bin, hard links of the bin directory's) and ld's
  # reference linker scripts. The POS compiler is given /pos/sdk/bin/as and
  # ld (pos/toolchain/packages/gcc/build.sh), and ld has its default scripts
  # built in: with tooldir the sdk prefix itself, there is no
  # /pos/sdk/x86_64-pc-linux-gnu, and the scripts are in
  # /pos/sdk/lib/ldscripts.
  pkg_compile tooldir="$sdk_prefix"
  pkg_install tooldir="$sdk_prefix"
  # ld's libdep plugin is a shared library only: without them it is an
  # archive in the directory bfd loads plugins from.
  rm -r "${dest_dir}${sdk_prefix}/lib/bfd-plugins"
}
