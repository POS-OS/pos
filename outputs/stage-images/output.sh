# The optional stages, each an image of the build's base stages.
output() {
  sysext_stage network core-libs system
  sysext_stage container core-libs system
}
