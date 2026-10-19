pkg() {
  # less is the pager for man and systemd. Regex matching uses core-libs pcre2.
  pkg_autotools --with-regex=pcre2
}
