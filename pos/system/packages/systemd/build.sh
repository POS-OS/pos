pkg() {
  # prefix is where systemd looks for its own units, generators and binaries
  # (the separate rootprefix option is gone). Configuration stays in /etc and
  # state in /var.
  #
  # systemd bakes in paths to programs it execs, defaulting to /usr/bin or
  # /usr/sbin. The *-path options move the ones POS ships: kmod from kmod,
  # loadkeys and setfont from kbd, the rest from util-linux (BUILD.md
  # "Prefix"). quotaon, quotacheck and kexec are not in POS and keep their
  # dead defaults. The keymaps localectl lists are kbd's, /pos/share/kbd
  # (prepare.sh adds it to the fixed /usr directories).
  # Programs a unit names without a path (ExecStart=systemd-tmpfiles) are
  # looked up in the built-in search path, /usr/local and /usr; POS's bin
  # directories are appended to it (extra-exec-search-path), which also
  # gives services and user sessions their PATH. Without them only a system
  # with links in /usr/bin (pos-fedora) finds those programs, not POS's own
  # root or its initramfs.
  #
  # Its pam.d files go where POS pam reads vendor configuration
  # (VENDORDIR/pam.d, pos/core-libs/packages/pam sets VENDORDIR=/pos/share/pam); the meson
  # default /pos/lib/pam.d is not on pam's search path.
  #
  # The boot loader (systemd-boot and the EFI stub) is built: bootctl installs
  # it from /pos/lib/systemd/boot/efi. It is made with pyelftools, a build
  # tool, so it needs no EFI library.
  #
  # Disabled: SysV compatibility (runlevel targets, legacy tmpfiles),
  # documentation (docbook toolchain), and every feature whose library is
  # not built yet (curl, idn2, gnutls, p11-kit, fido2, tpm2, qrencode,
  # microhttpd, xkbcommon, bpf, glib, lz4, selinux, apparmor, audit).
  #
  # libcryptsetup is the storage stage's, an optional one: systemd dlopens
  # it, so systemd-cryptsetup, the crypttab generator, cryptenroll and
  # homed's LUKS volumes work once the stage is enabled and fail without
  # it, as with the other dlopen'd libraries.
  #
  # Note for tmpfiles: a C line without a source copies from /usr/share/factory,
  # which does not exist on POS. Lines shipped by POS give the source
  # explicitly (/pos/share/factory/...).
  pkg_meson \
        -Dmode=release \
        -Dsplit-bin=true \
        -Dextra-exec-search-path="${prefix}/sbin:${prefix}/bin" \
        -Dcompat-sysv-interfaces=false \
        -Dkmod-path="${prefix}/bin/kmod" \
        -Dloadkeys-path="${prefix}/bin/loadkeys" \
        -Dsetfont-path="${prefix}/bin/setfont" \
        -Dmount-path="${prefix}/bin/mount" \
        -Dumount-path="${prefix}/bin/umount" \
        -Dsulogin-path="${prefix}/sbin/sulogin" \
        -Dswapon-path="${prefix}/sbin/swapon" \
        -Dswapoff-path="${prefix}/sbin/swapoff" \
        -Dagetty-path="${prefix}/sbin/agetty" \
        -Dnologin-path="${prefix}/sbin/nologin" \
        -Ddefault-user-shell="${prefix}/bin/bash" \
        -Ddebug-shell="${prefix}/bin/sh" \
        -Dfallback-hostname=pos \
        -Dpamlibdir="${prefix}/lib/security" \
        -Dpamconfdir="${prefix}/share/pam/pam.d" \
        -Drpmmacrosdir=no \
        -Dman=disabled \
        -Dhtml=disabled \
        -Dtests=false \
        -Dinstall-tests=false \
        -Dbootloader=enabled \
        -Dukify=disabled \
        -Dkernel-install=true \
        -Dseccomp=enabled \
        -Dkmod=enabled \
        -Dpam=enabled \
        -Dacl=enabled \
        -Dblkid=enabled \
        -Dfdisk=enabled \
        -Dopenssl=enabled \
        -Delfutils=enabled \
        -Dpcre2=enabled \
        -Dzlib=enabled \
        -Dbzip2=enabled \
        -Dxz=enabled \
        -Dzstd=enabled \
        -Dlz4=disabled \
        -Dlibcryptsetup=enabled \
        -Dlibcurl=disabled \
        -Dlibidn2=disabled \
        -Dgnutls=disabled \
        -Dp11kit=disabled \
        -Dlibfido2=disabled \
        -Dtpm2=disabled \
        -Dqrencode=disabled \
        -Dmicrohttpd=disabled \
        -Dxkbcommon=disabled \
        -Dbpf-framework=disabled \
        -Dglib=disabled \
        -Ddbus=disabled \
        -Dselinux=disabled \
        -Dapparmor=disabled \
        -Daudit=disabled \
        -Dsmack=false \
        -Dima=false \
        -Dhomed=disabled \
        -Dremote=disabled \
        -Dimportd=disabled \
        -Dmountfsd=false \
        -Dnsresourced=false

  # libsystemd and libudev, with their headers and .pc files, are
  # systemd-libs, the base stage's: util-linux, procps and shadow link them
  # without the base needing init (BUILD.md "Base stage").
  local libs f
  libs=$(pkg_output systemd-libs)
  mkdir -p "${libs}${prefix}/lib/pkgconfig" "${libs}${prefix}/include"
  for f in lib/libsystemd.so* lib/libudev.so* lib/pkgconfig/libsystemd.pc \
           lib/pkgconfig/libudev.pc include/systemd include/libudev.h; do
    mv "${dest_dir}${prefix}"/$f "${libs}${prefix}/${f%/*}/"
  done
}
