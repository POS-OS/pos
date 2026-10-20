# autoreconf generates the build system. sshd_config, installed as the
# shipped default, turns PAM on: logins get the default PAM stack and a
# logind session (pam_systemd), as console logins do.

prep() {
  sed -i 's/^#UsePAM no$/UsePAM yes/' sshd_config
  grep -qx 'UsePAM yes' sshd_config || {
    echo "openssh: no #UsePAM line in sshd_config to turn on" >&2
    exit 1
  }
  prep_gen
}
