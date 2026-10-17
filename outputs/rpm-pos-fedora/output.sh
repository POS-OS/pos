# pos and pos-sdk as the base of a Fedora system, in place of the Fedora
# packages POS replaces: pos-fedora provides what they provide, links their
# paths in /usr to /pos, and conflicts with them. On a system built with
# it, dnf installs only what POS does not have. The systems it is for
# build with POS's own tools, so it requires the sdk too.
#
# fedora lists the Fedora packages by POS package; a line counts when its
# POS package is in the stages:
#   <POS package> <Fedora package>...
# Making it needs network: the provides and files of the Fedora packages
# come from Fedora's repositories. The links, the provides and the claims
# dropped are written next to the package, as pos-fedora.links, .provides
# and .unmet. BUILD.md "RPM packages".

# Query Fedora's repositories for the latest x86_64 and noarch packages.
# Inputs:
#   $@    arguments passed to dnf repoquery
fedora_query() {
  dnf repoquery -q --latest-limit=1 --arch=x86_64,noarch "$@"
}

output() {
  local claims fedora p s names
  local -a claimed=() n
  local -A in_build=()
  claims=$(output_dir)/fedora
  fedora=$(rpm -E %fedora)
  for s in "${stages[@]}"; do
    [[ -d $bdir/assemble/$s/pos ]] || die "$output: stage $s is not assembled in $bdir"
    while read -r p; do
      p=${p%%#*}
      p=${p//[[:space:]]/}
      [[ -n $p ]] && in_build[$p]=1
    done <"$base/stages/$s/packages"
  done
  rpm_paths assemble pos >"$work/paths"

  # The Fedora packages POS replaces, for the POS packages in the stages.
  while read -r p names; do
    p=${p%%#*}
    [[ -n $p && -n ${in_build[$p]:-} ]] || continue
    read -ra n <<<"${names%%#*}"
    claimed+=("${n[@]}")
  done <"$claims"
  ((${#claimed[@]})) || die "$claims lists nothing for ${stages[*]}"
  printf '%s\n' "${claimed[@]}" | sort -u >"$work/claimed"

  # What they provide, from Fedora's repositories, and every path in Fedora
  # with the package that owns it.
  fedora_query --qf '@%{name} %{evr}\n%{provides}\n' "${claimed[@]}" >"$work/fedora.provides"
  for p in "${claimed[@]}"; do
    grep -q "^@$p " "$work/fedora.provides" || die "$claims: no package $p in Fedora $fedora"
  done

  # The sonames and symbol versions of the POS shared libraries, from rpm's
  # own generator, as Fedora's packages get theirs.
  for s in "${stages[@]}"; do
    find "$bdir/assemble/$s/pos" -type f -name '*.so*' -exec sh -c '
      for f; do if [ "$(head -c 4 "$f")" = "$(printf "\177ELF")" ]; then echo "$f"; fi; done' sh {} +
  done | /usr/lib/rpm/elfdeps --provides | sort -u >"$work/pos.sonames"

  # A claim stands only if POS has every versioned soname and symbol version
  # the Fedora package provides; a Fedora binary linked against it would
  # not load otherwise. Unversioned plugin names and *_PRIVATE versions are
  # internal to the Fedora package and not checked.
  awk '/^@/ {n = $1; sub(/^@/, "", n); next}
       $1 !~ /^\// && $1 ~ /\.so\.[0-9]/ && $1 !~ /PRIVATE/ {print n, $1}' "$work/fedora.provides" |
    sort -u | awk 'NR == FNR {have[$1] = 1; next} !have[$2]' "$work/pos.sonames" - >"$work/unmet"
  if [[ -s $work/unmet ]]; then
    awk '{c[$1]++; if (!s[$1]) s[$1] = $2} END {for (n in c) print n, c[n], s[n]}' "$work/unmet" | sort |
      while read -r p c s; do
        echo "pos-fedora: not replacing $p: POS lacks $c of its sonames and symbol versions ($s ...)" >&2
      done
    awk '{print $1}' "$work/unmet" | sort -u | comm -23 "$work/claimed" - >"$work/claimed.ok"
    mv "$work/claimed.ok" "$work/claimed"
  fi
  fedora_query --setopt=optional_metadata_types=filelists --qf '@%{name}\n%{files}\n' >"$work/fedora.files"

  # Paths only Fedora packages pos-fedora does not replace have. pos-fedora
  # does not link those, so such a package installs next to it without a
  # file conflict. A path a replaced package also has is linked: the
  # alternatives that have it too (coreutils-single for coreutils) provide
  # the replaced name, so pos-fedora conflicts with them anyway.
  awk 'NR == FNR {c[$1] = 1; next}
       /^@/ {claimed = c[substr($0, 2)]; next}
       NF {print (claimed ? "c" : "u"), $0}' "$work/claimed" "$work/fedora.files" |
    awk '{p = substr($0, 3)} $1 == "c" {c[p] = 1; next} {u[p] = 1}
         END {for (p in u) if (!c[p]) print p}' | sort -u >"$work/fedora.taken"

  # The links: programs into /usr/bin (Fedora's /usr/sbin is a link to it),
  # libraries and the loader into /usr/lib64 (/lib64 is a link to it). The
  # loader link is what makes Fedora's binaries, which request
  # /lib64/ld-linux-x86-64.so.2, run on POS glibc.
  awk '$1 != "d" {print $2}' "$work/paths" | awk -F/ '
    ($3 == "bin" || $3 == "sbin") && NF == 4 {print "/usr/bin/" $4, "../../pos/" $3 "/" $4}
    $3 == "lib" && NF == 4 && ($4 ~ /\.so\./ || $4 ~ /^ld-linux/) {print "/usr/lib64/" $4, "../../pos/lib/" $4}
  ' | sort -u -k1,1 | join -v1 - "$work/fedora.taken" >"$work/links"

  # Provides:
  # - the claimed packages' own provides (names, name(x86-64), config(),
  #   rtld(GNU_HASH), user() and group(), ...) at Fedora's versions, so
  #   versioned requirements match. Not their sonames and paths, which
  #   describe Fedora's files, and not bundled().
  # - the sonames and symbol versions of the POS libraries: a Fedora binary
  #   that needs a symbol version POS glibc does not have is not satisfied.
  # - the linked paths under the names Fedora's merged directories give them.
  {
    awk 'NR == FNR {c[$1] = 1; next}
         /^@/ {n = $1; sub(/^@/, "", n); next}
         c[n] && NF && $1 !~ /^\// && $1 !~ /\.so[.(]/ && $1 !~ /^bundled\(/' \
      "$work/claimed" "$work/fedora.provides"
    cat "$work/pos.sonames"
    awk '$1 ~ /^\/usr\/bin\// {n = substr($1, 10); print "/bin/" n; print "/usr/sbin/" n; print "/sbin/" n}' "$work/links"
    awk '$1 ~ /^\/usr\/lib64\// {print "/lib64/" substr($1, 12)}' "$work/links"
  } | sort -u >"$work/pos-fedora.provides"

  # The system's os-release is POS's (/pos/lib/os-release), in place of
  # Fedora's fedora-release, which the claims list. fedora-release required
  # Fedora's repositories (fedora-repos); pos-fedora does in its place.
  # dnf's release version is the version of the system-release provider
  # (fedora-release's is 44, pos-fedora's the build ID) unless a
  # system-release(releasever) provide gives it.
  local osrel_install= osrel_files= osrel_tags=
  if grep -q " /pos/lib/os-release$" "$work/paths"; then
    osrel_install='ln -s ../../pos/lib/os-release %{buildroot}/usr/lib/os-release
ln -s ../usr/lib/os-release %{buildroot}/etc/os-release'
    osrel_files='/usr/lib/os-release
/etc/os-release'
    osrel_tags="Requires: fedora-repos
Provides: system-release(releasever) = $fedora"
  fi

  # Fedora curl, dnf, rpm, and python search /etc/pki for CA certificates.
  # When the stages provide /pos/share/ca-certificates/ca-bundle.crt, supply
  # the compatibility symlinks in /etc/pki so HTTPS requests work in Fedora
  # images and toolboxes.
  local pki_install= pki_files=
  if grep -q " /pos/share/ca-certificates/ca-bundle.crt$" "$work/paths"; then
    pki_install='mkdir -p %{buildroot}/etc/pki/ca-trust/extracted/pem %{buildroot}/etc/pki/tls/certs
ln -s ../../../../../pos/share/ca-certificates/ca-bundle.crt %{buildroot}/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
ln -s ../../pos/share/ca-certificates/ca-bundle.crt %{buildroot}/etc/pki/tls/cert.pem
ln -s ../../../pos/share/ca-certificates/ca-bundle.crt %{buildroot}/etc/pki/tls/certs/ca-bundle.crt'
    pki_files='%dir /etc/pki/ca-trust
%dir /etc/pki/ca-trust/extracted
%dir /etc/pki/ca-trust/extracted/pem
/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
%dir /etc/pki/tls
%dir /etc/pki/tls/certs
/etc/pki/tls/cert.pem
/etc/pki/tls/certs/ca-bundle.crt'
  fi

  {
    rpm_spec_head pos-fedora "POS as the base of a Fedora system" \
      "Requires: pos = $evr" "Requires: pos-sdk = $evr" "Requires: filesystem"
    [[ -z $osrel_tags ]] || echo "$osrel_tags"
    sed 's/^/Provides: /' "$work/pos-fedora.provides"
    sed 's/^/Conflicts: /' "$work/claimed"
    cat <<EOF

%description
POS build $id in place of the Fedora $fedora packages it replaces:
$(xargs <"$work/claimed" | fold -s -w 72)

It provides what those provide, links their programs and libraries in
/usr to /pos, and conflicts with them. Fedora packages that need them use
POS; dnf installs only what POS does not have. The POS loader also
searches /usr/lib64, after /pos/lib (/etc/pos/ld.so.conf, also as
/etc/ld.so.conf for tools that read the library path there), where Fedora
packages installed next to POS put their libraries. The system's
os-release is POS's.

%install
mkdir -p %{buildroot}/usr/bin %{buildroot}/usr/lib %{buildroot}/usr/lib64 %{buildroot}/etc/pos
while read -r path target; do
  ln -s "\$target" "%{buildroot}\$path"
done <'$work/links'
printf '%s\n' /pos/lib /usr/lib64 >%{buildroot}/etc/pos/ld.so.conf
chmod 0644 %{buildroot}/etc/pos/ld.so.conf
ln -s pos/ld.so.conf %{buildroot}/etc/ld.so.conf
$osrel_install
$pki_install

# The POS loader finds what is not in /pos/lib through its cache only, so
# the cache is updated after every package that adds libraries, before
# the scriptlets of later packages run their programs. Lua, as Fedora's
# glibc does: -p with a program would pass it the package count.
%post -p <lua>
rpm.execute("/pos/sbin/ldconfig")

%filetriggerin -p <lua> -- /usr/lib64 /pos/lib
rpm.execute("/pos/sbin/ldconfig")

%filetriggerpostun -p <lua> -- /usr/lib64 /pos/lib
rpm.execute("/pos/sbin/ldconfig")

%files
%dir /etc/pos
%config(noreplace) /etc/pos/ld.so.conf
/etc/ld.so.conf
$osrel_files
$pki_files
$(awk '{print $1}' "$work/links" | rpm_escape)
EOF
  } >"$work/pos-fedora.spec"
  rpm_build pos-fedora

  cp "$work/links" "$bdir/rpm/pos-fedora.links"
  cp "$work/pos-fedora.provides" "$bdir/rpm/pos-fedora.provides"
  cp "$work/unmet" "$bdir/rpm/pos-fedora.unmet"
}
