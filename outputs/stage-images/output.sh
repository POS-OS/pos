# The optional stages, each an image over the build's core-libs, base and
# system stages.
output() {
  sysext_stage network core-libs base system
  sysext_stage container core-libs base system
  sysext_stage storage core-libs base system
}
