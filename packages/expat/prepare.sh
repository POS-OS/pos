# libexpat keeps the library in the expat/ subdirectory; autoreconf
# generates its build system there.

prep() {
  (cd expat && prep_gen)
}
