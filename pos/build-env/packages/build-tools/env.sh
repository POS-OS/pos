# Sourced by _pkg_setup (and _prep_setup) where the build tools are an
# extras reference's: its programs, then /pos's, ahead of the tools
# image's, which holds only the host-requires packages declare. A
# profile's env.sh, such as pos-link's, puts the build's own prefix and
# the sdk in front.
export PATH="${tools_prefix}/bin:${pos_prefix}/bin:${pos_prefix}/sbin:$PATH"
