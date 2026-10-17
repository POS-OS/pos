# The stages extracted into /pos, the root layout around it, and what a
# first boot fills in: the factory defaults and the users and groups.
output() {
  fs_stages
  fs_layout "$(output_dir)/layout"
  fs_factory
  fs_sysusers
  fs_archive
}
