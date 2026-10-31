pkg() {
  # shadow owns the account database tools (useradd, passwd, chage, gpasswd,
  # newgrp/sg, vipw). login, su, nologin, chfn and chsh come from util-linux
  # and groups from coreutils, so those are dropped below (BUILD.md "System
  # stage"). --enable-vendordir records the factory path. Reading login.defs
  # from there when /etc/login.defs is absent needs libeconf, which is not
  # built yet.
  pkg_autotools \
    --disable-static \
    --with-libpam \
    --with-bcrypt \
    --with-yescrypt \
    --without-libbsd \
    --without-su \
    --without-selinux \
    --without-audit \
    --with-group-name-max-length=32 \
    --enable-vendordir="${prefix}/share/factory/etc"

  for f in login chfn chsh groups; do
    rm -f "${dest_dir}${prefix}/bin/${f}"
  done
  rm -f "${dest_dir}${prefix}/sbin/nologin"
  # The PAM configuration is POS's (pos-integration), as is every service's.
  # shadow's includes files for programs util-linux provides (login, chfn,
  # chsh), with modules POS does not have.
  rm -r "${dest_dir}/etc/pam.d"
  # Man pages for those, and the ones man-pages provides (passwd.5, getspnam.3).
  # The git tree carries only DocBook sources; roff pages are generated at
  # release time and need xsltproc plus the DocBook toolchain (--enable-man),
  # which POS leaves out like it does for systemd and dbus. So there is
  # usually nothing here.
  if [[ -d ${dest_dir}${prefix}/share/man ]]; then
    find "${dest_dir}${prefix}/share/man" -regextype posix-extended \
         -regex '.*/(login|chfn|chsh|groups|nologin)\.[18](\..*)?' -delete
    find "${dest_dir}${prefix}/share/man" -regextype posix-extended \
         -regex '.*/(getspnam\.3|passwd\.5)(\..*)?' -delete
  fi

  # login (util-linux) sets PATH from login.defs: ENV_SUPATH for root,
  # ENV_PATH for the rest. They are the default ones with POS's bin
  # directories after them, as systemd's search path (pos/system/packages/systemd)
  # and sudo's secure_path.
  defs=${dest_dir}${sysconfdir}/login.defs
  sed -i -e "s|^ENV_SUPATH\t.*|ENV_SUPATH\tPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${prefix}/sbin:${prefix}/bin|" \
         -e "s|^ENV_PATH\t.*|ENV_PATH\tPATH=/usr/local/bin:/usr/bin:/bin:${prefix}/bin|" "$defs"
  grep -q "^ENV_SUPATH.*${prefix}/sbin" "$defs" && grep -q "^ENV_PATH.*${prefix}/bin" "$defs" ||
    { echo "shadow: $defs has no ENV_SUPATH/ENV_PATH to set" >&2; exit 1; }

  # useradd gives a user subordinate ids (SUB_UID_MIN.. in login.defs) only
  # where /etc/subuid and /etc/subgid exist, as Fedora's setup package ships
  # them: empty, through the factory tree. Rootless containers map their
  # users into them with newuidmap and newgidmap.
  install -m 0644 /dev/null "${dest_dir}${sysconfdir}/subuid"
  install -m 0644 /dev/null "${dest_dir}${sysconfdir}/subgid"

  # expiry(1) was removed upstream; chage -l covers it.
  pkg_setuid "${prefix}/bin/passwd" "${prefix}/bin/chage" "${prefix}/bin/gpasswd" \
             "${prefix}/bin/newgrp" "${prefix}/bin/newuidmap" "${prefix}/bin/newgidmap"
}
