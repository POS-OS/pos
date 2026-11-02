# Building
`./build` (`buildsys/build.sh`) builds the release: every stage (see
"Trees"), each assembled into one archive, and the outputs in `outputs/`
(images, disks, RPM packages; see "Build outputs"). It
runs on the host or in any toolbox and needs the host's podman, which it
reaches through `flatpak-spawn --host` from inside a toolbox, as the
`toolbox` CLI does. Every step of a build runs in a container of its own
(see "Build containers").

    $ ./build plan                 # what run would build, in order
    $ ./build run --new            # a new build, with the toolchain reference pos-sdk made
    $ ./build run                  # build and assemble every stage
    $ ./build run core-libs        # one stage
    $ ./build run zlib             # one package (and what it needs)
    $ ./build prepare              # download and prepare sources ahead of a run
    $ ./build status
    $ ./build output               # make the outputs of the current build again
    $ ./build output rpm-pos       # one output: the pos RPM package
    $ devtools/install.sh          # install the archives as /pos
    $ devtools/try-rpm.sh          # try out the RPM packages
    $ ./build output fedora-toolbox  # POS as a toolbox image
    $ devtools/vm.sh               # boot the vm-disk-dnf disk in a VM
    $ devtools/vm.sh -c devtools/smoke.sh  # check it: boot, run the checks, power off
    $ buildsys/compare-builds.sh <id> <id>  # what differs between two builds

## Builds
A build has an ID (a timestamp) and keeps everything under
`work/builds/<id>`: `dest/<package>` staging trees, `debug/<package>` debug
info (see "Debug info"), `logs/<package>.log`, the stage archives
`pos-<stage>-<stem>.tar.zst` with their `pos-debug-<stage>-<stem>.tar.zst`,
and what the outputs make: the RPM packages in `rpm/`, image archives
`pos-<output>-<stem>.tar.zst` and disks `pos-<output>-<stem>.qcow2`, with
their logs `logs/output-<output>.log`, where `<stem>` is
`<major>.<minor>-<build>.<release>` (see "Build numbers"). `work/builds/current`
points at the build that `run` continues. `run --new` starts another, of
the project's pipeline: a pos build in pos, a toolchain build in pos-sdk,
an extras build in pos-extras (`info`: `pipeline`; see "Toolchain",
"Extras"). A
package is built once per build; `./build rebuild <package>` drops it
from the current build so the next `run` builds it again. Packages that were
built against it are not rebuilt. A package that a bootstrap package
stands in for is rebuilt with what replaced the bootstrap package:
`rebuild systemd util-linux`, since util-linux, built against systemd,
otherwise takes util-linux-bootstrap's place in systemd's environment
("systemd: needs systemd"). Builds from before build containers
(their `info` has no `tools-image`) cannot be continued; `status` and
`reference` still work on them.

## Build numbers
A build is identified by its ID, the timestamp it was created with. An OS
build, one that ships, also gets a BUILD number: `VERSION` holds the
number main's next numbered build gets. The project owners number a build
with `./build tag`, or `./build publish`, which also publishes it (see
"Releases"):

1. `./build validate` checks the current build from what its producers
   recorded. Every producer records what it made in `made/<name>`
   (`package-<package>`, `stage-<stage>`, `output-<output>`): the
   commit it was made from and whether the tree had uncommitted changes,
   and the engine's commit when it is another checkout's (see "Engine").
   It drops its record and `complete` before it starts, so a failed one
   leaves neither. A default `run` that finishes records `complete`;
   `rebuild` drops the records of the dropped packages and of everything
   made from packages.
   The build can be numbered when it is a build of the project's
   pipeline (a pos build in pos, a toolchain build in pos-sdk) with
   `complete`, every record names its commit (and engine) with a clean
   tree, and its BUILD (`VERSION` at its commit) is above every `main-*`
   tag.
2. The build's commit is tagged `main-<BUILD>`, an annotated tag with the
   build ID, its identifier, the references and whether checks were
   skipped.
3. `./build bump` commits `VERSION` with the next BUILD, as pos-bot. Run
   it alone when `tag` or `publish` failed after tagging.

Checks belong to their producer. An output with a disk checks it with
`disk_check`, a script that `devtools/vm.sh` runs in the booted disk
(vm-disk and vm-disk-dnf: `devtools/smoke.sh`); the output is recorded
only when it passes. `run --no-checks` and `output --no-checks` skip
checks and record the output `unchecked`, which `validate --unchecked`,
`tag --unchecked` and `publish --unchecked` accept.

Every build carries the version of `VERSION` at the commit it was created
at, tagged or not: a tag changes no artifact. `VERSION` holds the
product version (`PRODUCT_VERSION=1.0`, `<major>.<minor>`), the product
release (`PRODUCT_RELEASE`: a static string, or empty for
`<branch>.<timestamp>`), the service release revision (`REVISION`, 0
for now), the RPM release number (`RPM_RELEASE`) and `BUILD`. A new build
records them in its `info` (`product-version`, `product-release`,
`release-type`, `revision`, `rpm-release`, `build-number`), with the
default product release made of the branch (what rpm does not allow in a
release becomes `_`) and the build ID as `20261017-1524`. `run --new`
refuses a commit whose `VERSION` lacks a field or has a malformed one.
Builds made before `VERSION` had a product version have no names for
their artifacts: `run` does not continue them and `output` does not make
their outputs; `status`, `validate` and `reference` still work on them.

The version names the build (`buildsys/buildinfo.sh`), for product
version 1.0, BUILD 3, revision 0 and release `main.20261017-1524`:

* the identifier: `1.0.3.0.main.20261017-1524`
  (`<product version>.<build>.<revision>.<release>`), in the tag and
  os-release;
* artifacts: `<artifact>-<major>.<minor>-<build>.<release>`, in the build
  directory and the release library alike:
  `pos-system-1.0-3.main.20261017-1524.tar.zst`;
* RPM packages: version `<major>.<minor>.0`, release
  `<rpm release>.<release>` without the timestamp's `-`, which rpm does not
  allow: `pos-1.0.0-1.main.202610171524.x86_64.rpm`. Updates of a product
  version sort by the RPM release number first, then the release: raise
  `RPM_RELEASE` for a branch from main on the same product version, and
  for each new static product release. A static product release has only
  what rpm allows (letters, digits and `. _ + ~ ^`);
* os-release (assembled into the stage that has it; os-release(5)):
  `PRETTY_NAME="POS 1.0"`, `VERSION="main.20261017-1524"`,
  `VERSION_ID=1.0`, `BUILD_ID=1.0.3.0.main.20261017-1524`,
  `POS_BUILD=3.0` (the OS build, `<build>.<revision>`, which has no
  field of its own) and `RELEASE_TYPE`, `development` for a
  `<branch>.<timestamp>` release and `stable` for a static one. `NAME`
  stays `POS`, without a version;
* podman images: tagged `:<id>` and with the product version (`:1.0`),
  which moves to the build that made the image last, labelled
  `pos.version` with the identifier.

`tag` runs on main, with `VERSION` at HEAD still the build's BUILD. Every
commit between two bumps carries the same BUILD; only the tagged one is
that build. Neither command pushes.

## Releases
`./build publish [--unchecked]` numbers the current build as `tag` does
and copies its artifacts into the release library, the `release-dir`
setting (a local directory for now), which holds a directory per
project: `<release-dir>/<project>/<release>`, the release named as the
artifacts are (`pos/1.0-3.main.20261017-1524`). The release holds the
build's `info`, everything named after it (stage and debug archives,
image archives with their package lists, disks, the recipes and engine
archives), its source archives, its RPM packages in `rpm/`, its
reference archive (`pos-ref-<kind>-<id>.tar.zst`, as `./build reference`
writes it: a pos release's core-libs and base, a pos-sdk release's toolchain
packages, which is what a pos-sdk release ships), and `SHA256SUMS`. It refuses
a release that is there already, and one whose RPM packages would not
update those of a release of the same product version there (the same
version-release, or a lower RPM release number). The release is filled
under a temporary name and appears once the tag is made; then `VERSION`
is bumped.

The toolbox image is not published: `devtools/release-toolbox.sh
<release>` makes it in podman from the release's container-fs-dnf, with
this checkout's `outputs/fedora-toolbox`, tagged with the release and the
product version:

    $ devtools/release-toolbox.sh 1.0-3.main.20261017-1524
    $ toolbox create -i localhost/pos-fedora-toolbox:1.0 <name>

## Settings
Settings of `./build` are lines of `<key> <value>` in
`~/.config/pos/build.conf`, or in the file `POS_BUILD_CONFIG` names, and
in `<project>.conf` next to it (`pos.conf`, see "Engine"), whose lines
replace the shared file's for that project.
`build.conf.dist` lists them; copy it there and edit. Each setting's
environment variable overrides the file, for a single run. Only a new
build reads them: what it uses is recorded in its `info`, so a build
keeps its settings when the file changes. The file is read as data, and
an unknown key is an error.

| key | variable | default |
| --- | --- | --- |
| `fedora-release` | `POS_FEDORA_RELEASE` | 44 |
| `tools-image` | `POS_TOOLS_IMAGE` | `registry.fedoraproject.org/fedora:<release>` |
| `reference-dir` | `POS_REFERENCE_DIR` | none: no reference store |
| `toolchain-reference` | `POS_TOOLCHAIN_REFERENCE` | the store's default (see "Reference builds"); a build ID or `<project>/<release>`; `none`: a build with Fedora's compiler |
| `pos-reference` | `POS_POS_REFERENCE` | the project file's `pos-reference`; else a pos or extras build: the store's default, else its toolchain reference's; a toolchain build: none, an error (see "Reference builds"); a build ID or `<project>/<release>` |
| `tools` | `POS_TOOLS` | the store's default extras reference; `fedora` without one or without a pos reference; `fedora`: host-base in the tools image; an extras reference, a build ID or `<project>/<release>`: its tools and the pos reference's base (see "Build tools") |
| `release-dir` | `POS_RELEASE_DIR` | none: `publish` needs it; the release library of every project, a directory each; read by `publish` and to restore references, not recorded by builds |
| `download-dir` | `POS_DOWNLOAD_DIR` | `work/downloads`: the sources' release archives (see "Release archives"); not recorded by builds |
| `engine-checkout` | `POS_ENGINE_CHECKOUT` | none: the pos checkout another project's `./build` takes the engine from (see "Engine"); read by that `./build` |

## Engine
`buildsys/` is the engine: it resolves, runs the steps in containers,
keeps the references and fetches the sources. What it builds is a
project, a checkout with the layout below (`pos/<tree>`, `outputs/`,
`VERSION`, `work/`) and a `project` file of `<key> <value>` lines: the
checkout the environment variable `POS_PROJECT` names, else the one the
engine is in. Its `name` (pos) names the project's settings
(`<name>.conf`, see "Settings"), its tools images and containers
(`localhost/<name>-tools:<id>`, `<name>-<id>-<step>`) and its recipes
archive.

pos builds itself with its own engine. Another project runs the engine of
a pos checkout with `POS_PROJECT` set to itself: its `./build` pins the
engine, an `engine <pos commit>` line in its `project` file, checked out
from the pos checkout the `engine-checkout` setting names. Its builds are kept in its own `work/`,
and their `info` records the engine's commit (`engine`), as every
record a producer makes does (see "Build numbers"). A change to the
engine's `buildsys/` makes such a build's records dirty, as one to the
project does. `buildsys/compare-builds.sh` takes build IDs of the
project the same way.

A project has the packages of one pipeline, which a `pipeline` line of
its `project` file names: `pipeline toolchain` in pos-sdk, `pipeline
extras` in pos-extras, none (pos) in pos. A `pos-reference` line pins
the pos reference of its builds (see "Reference builds"). The other
pipelines' packages are known from the references, by the `meta` each installed in `<prefix>/lib/pos/packages/<package>/`, of the
pipeline the reference's `info` names, and taken from them as any
reference package is; a capability nothing in the project provides is checked when
a build resolves it. A package's `env.sh` is installed beside its `meta`,
and a build that takes the package from a reference sources that copy.

## Trees
What POS builds is in `pos/`, divided into trees: `pos/<tree>/` has any
of `packages/<name>/` (recipes, see "Packages"), `src/<source>` with
`src/<source>.upstream` (sources, see "Sources") and `stage`, the member
list of the stage named after the tree.

| Tree | What it holds |
| --- | --- |
| `core-libs`, `base`, `system` | the stages: their member lists, and the packages and sources of their members |
| `network`, `container`, `storage` | the optional stages (see "Network stage", "Container stage", "Storage stage"), as the stages above |
| `common` | sources of packages of several trees: gnulib |
| `build-env` | the host and profile packages builds require (host-base, build-tools, host-toolchain, gcc-host, pos-link) |

A package lives in the tree of the stage that ships it, and one no stage
ships by its role. The toolchain is the exception: core-libs lists
gcc-runtime, which a pos build takes from its toolchain reference; its
recipe is pos-sdk's (see "Toolchain"). binutils and gcc are pos-sdk's
alone, in `/apps/pos-sdk/<version>`; no pos stage lists them. A stage's `stage` file lists packages of any tree.

Package names are unique across trees, and so are source names; meta and
stage files name packages without their tree, so a package moves between
stages without edits elsewhere. A package's sources (`source`,
`with-sources`) are its own tree's or `common`'s. A source of another
tree is named with it, `<tree>/<source>`, which shows what crosses trees.

## Sources
POS builds from upstream source, not from upstream releases, so it does
the release preparation itself. A source goes through three steps:

1. Sync: `pos/<tree>/src/<source>` holds exactly the files upstream's git
   tracks, and `src/<source>.upstream` next to it records the branch
   (`ref`), `commit`, commit `date` and `url` it came from. Both are
   committed. Upstream's submodules are part of the tree, except those
   that are sources of their own (gnulib, paxutils), which packages take
   from their `src/<name>`.
2. Prepare: what upstream's release process adds to a release tarball.
   `prepare.sh` of the package named after the source works on a copy of
   the committed source, with helpers from `buildsys/prepare.sh`:
   `prep_pull` runs gnulib bootstrap's pull phase or `autopull.sh`
   (translations, submodule hooks), `prep_gen` generates the build system,
   `prep_version` writes `.tarball-version`, `prep_cargo_vendor` vendors
   a Rust source's crates (`cargo vendor`). Files gnulib-tool links to
   gnulib (`pos/common/src/gnulib`) are copied, so the prepared tree stands
   alone. Prepare runs in a build container with network access, which has
   the recipes, the committed source, gnulib and the tree to prepare, into which the package's
   `with-sources` are copied first (tar's and cpio's bootstrap imports
   files from `paxutils`); `prepare-requires` in the meta lists its Fedora
   packages.
3. Build: from the prepared tree when the source has a prepare recipe, from
   the committed source otherwise. A build needs no network.

Everything that changes or generates source files belongs to prepare:
autogen.sh, bootstrap and autoreconf, generators such as less's
`Makefile.aut`, and edits to upstream files (systemd's libseccomp version
check, shadow's `chsh.c`). A build recipe configures, compiles and installs
a tree it does not change. Sources that need none of that (glibc,
zlib, the meson and cmake packages, and bash, sqlite and sudo, which commit
their `configure`) have no prepare recipe and are built from their
committed source.

Prepared trees are kept in `work/sources/<source>/<key>`. The key is a hash
of the committed source tree, its `.upstream`, the prepare recipe, the
helpers, the `prepare-requires`, the committed gnulib for
packages that use gnulib, and the committed `with-sources`. A tree is prepared once for each key and shared by
every package built from that source (util-linux, util-linux-bootstrap),
every build that copies it into its own tree (`with-sources`), and later
builds. `run` prepares a source when it
first needs it; `./build prepare` does it ahead of time. Builds and
prepare use the committed state of a source, so uncommitted changes under
its `src/<source>` stop them.

The version prepare gives packages that take theirs from gnulib's
git-version-gen (coreutils, findutils, grep, gzip, sed, diffutils, patch)
is a snapshot name, not a release number: `<ref>-<commit date>-<commit>`,
for example `master-20260924-5eff02ecb19b` (`prep_version`). Other packages
keep the version their own source states. util-linux and logrotate carry
older copies of git-version-gen that accept only a version starting with a
digit; util-linux takes its version from `NEWS`. libseccomp's `main`
says `0.0.0` in `configure.ac` until a release sets it; its prepare
recipe sets the newest release in `CHANGELOG`, which is also the library's
soname (`libseccomp.so.2`) and `SCMP_VER_*`.

### Release archives
A source can instead be an upstream release archive, for what follows
upstream releases rather than its development (pos-sdk's toolchain,
see "Toolchain"). The meta of the package named after the source has
`archive <url> <sha256>` and `version <version>` (the release's, as
upstream numbers it), and the source has no `src/<source>` and no
prepare recipe: a release archive is what prepare makes of a tree.
Patches go in the package directory's `patches/`, `*.patch` applied with
`-p1` in name order. Changing the version is changing those two lines.

The archive is downloaded into the download directory (setting
`download-dir`) when a build first needs it, or by `./build prepare`,
in a build container with network access, and kept under the name
upstream gives it. It is checked against the sha256 when downloaded and
each time it is used; a file that does not match stops the build and is
left as it is. A build container without network unpacks it, with the
patches, into `work/sources/<source>/<key>`, keyed by the `archive` line
and the patches; the archive holds one top directory, which becomes the
tree. Builds use the tree as they use a prepared one.

Each package's metadata records the source it was built from:
`build-source <source> <key>`, the prepared or unpacked tree's key or
the committed tree's hash.

It also records `build-key <key>`, a hash of everything its build
container is given (`build_key`): the source's key and time and the
with-sources' keys; the recipe's directory, the recipe of its source (which
a bootstrap recipe sources) and `buildsys/pkg.sh`; each package of the
environment, a reference's by the reference, this build's by its
`build-key`; the env.sh scripts that set the build up; the tools image and
tools reference; and the prefixes. A build has no network, so two builds
of a package with the same key are builds of the same inputs. The paths of
the checkout and of the build directory are not in it: builds must not
depend on them. The build key is recorded only, for now; it is what a
build cache would reuse packages by.

## Source archives
`./build run --new --source-archives` creates a build that, after
assembling the stages, archives every source its packages were built from,
as recorded in their metadata: `pos-src-<source>-<key>.tar.zst`, the
prepared tree or the committed tree, and for a source from a release
archive the archive as downloaded, `pos-src-<archive>`, which its sha256
in the meta checks; its patches are in the recipes. It also archives the build recipes as
they are at `HEAD` (`buildsys`, the trees' `packages` and `stage`, `outputs`,
the docs) as
`pos-recipes-<stem>.tar.zst` (`<project>-recipes` in another project), with a warning if they changed since the build
started. An engine of another checkout is archived on its own, its
`buildsys` at `HEAD`, as `pos-engine-<stem>.tar.zst`. Together they are the source of the build's archives. Whether a
build writes them is chosen when it is created.

## Packages
A tree's `packages/<name>/` holds `build.sh`, the recipe, and `meta`, which declares
what the package needs and what it gives (format in `buildsys/resolve.sh`):

    build-requires gcc pos-link
    requires glibc ncurses readline
    provides util-linux-bootstrap
    obsoletes util-linux-bootstrap
    host-requires meson ninja-build

`requires` are run-time requirements, installed along with the package
wherever it is installed. `build-requires` are needed only to build it.
Every package provides its own name. When two available packages provide
what is required, the one the other obsoletes is not used. `host-requires`
are Fedora packages, in the build's tools image (see "Build containers");
the tools every build gets are `host-base`'s or `build-tools`' (see
"Build tools").

Go and Rust packages (the container stage's) build with Fedora's
compilers, from the tools image (`host-requires golang`, `rust cargo`):
POS builds neither yet. `pkg_go_env` (`buildsys/pkg.sh`) sets up a Go
build with the source's committed `vendor/` modules, and `pkg_cargo`
builds with cargo from the crates prepare vendored; both offline. Their
programs link with the environment's gcc and LDFLAGS, as C programs do:
against `/pos/lib`, with the POS loader as interpreter, and with a build
ID for the debug info. What cargo builds to run in the build, build
scripts and proc-macros, links with the host's `cc` instead
(`host-requires gcc`): rustc loads proc-macros into itself, on the tools
image's glibc, which may be older than POS's. `pkg_cargo` passes an
explicit `--target` for that, which keeps RUSTFLAGS to the target's crates.

Python modules (pos-extras) build with `pkg_python`: a wheel of the
source, made by the python3 on PATH with the build backend the recipe
requires (`build-requires setuptools`, `flit-core`), offline and without
an isolated build environment, then installed into the prefix with its
bytecode compiled for the installed paths.

A package is of its project's pipeline (see "Engine", "Toolchain").
`kind source` is a directory with only what makes a source, a prepare
recipe or an `archive`, for a source other packages copy into their tree
(mpc).

`run` picks a package whose requirements are all available (built in this
build, host packages, or from a reference build), builds it, and repeats
until the targets are built. Where several are ready, a package obsoleted
by another ready one waits. A build does not see the whole build history:
its `/pos` holds exactly the package's requirements, plus the run-time
requirements of those.

## Outputs
One build can produce several packages, as an rpm spec has sub-packages.
The main package lists them (`outputs gcc-runtime`); each has its own
package directory, with a `meta` of `kind output` and `output-of`, and no
`build.sh`. After the build, an output is a package like any other: its
own `dest/<name>`, requirements, provides, obsoletes and metadata, and a
stage lists it on its own. Wanting an output builds its main package;
`rebuild` of the main package drops its outputs too. An output installs
in the project's prefix, or in pos's with `prefix /pos` in its meta:
pos-sdk's gcc-runtime, which pos ships (see "Prefix").

The recipe installs each output into `$(pkg_output <name>)`. `pkg_finish`
then removes from the main package every file an output holds, so each file
belongs to one package and the recipe can install everything first.
Requirements an output provides are not part of its own build's
environment: gcc requires gcc-runtime, which it produces.

## Toolchain
The toolchain is gcc (with its gcc-runtime output) and binutils: the
packages of the toolchain pipeline. Their recipes are the
pos-sdk project's, whose `project` file says `pipeline toolchain`, which builds them with this engine (see "Engine"); pos
has no toolchain package of its own and knows them from its toolchain
reference. It is built apart from the rest, and a build is one of two
kinds (`info`: `pipeline`), its project's:

* A toolchain build (`run --new` in pos-sdk) builds the
  toolchain packages only. Its compiler is the toolchain reference's gcc, or
  Fedora's without one; it builds on the glibc of a pos reference, a
  stored pos build, with its kernel headers (linux-headers), and never
  builds either. Its pos reference is the one its `project` file pins
  (`pos-reference`), the oldest glibc the toolchain serves.
  `./build reference` stores it as the toolchain reference of later
  builds, which records the pos reference it was built on.
* A pos build (`run --new` in pos) builds every stage with the toolchain
  reference's toolchain, and never builds a toolchain package. Its own
  packages are all built from the checkout; core-libs, which lists
  gcc-runtime, is assembled with the toolchain reference's. Until it has built them, core-libs is the
  pos reference's: by default the store's.
  `./build reference` stores its core-libs and base as the pos reference
  of later toolchain and extras builds.

The interface between the two is a built pos: pos-sdk builds nothing of
pos, and pos nothing of the toolchain (see "Reference builds").

A build without a toolchain reference uses Fedora's compiler, the
`gcc-host` profile, which provides `gcc`: it runs Fedora's gcc with
`/pos` ahead of `/usr` in its search (`gcc-host/env.sh`). gcc obsoletes
`gcc-host`, and a host or profile package a toolchain reference package
obsoletes is not available, so with a toolchain reference its gcc is the
compiler. A pos build without one is the bootstrap of the first pos
reference: it builds packages, not stages: glibc, and linux-headers,
which glibc requires. From nothing, POS is built in four builds, two of
them in pos-sdk:

    pos$     POS_TOOLCHAIN_REFERENCE=none ./build run --new glibc  # glibc, linux-headers by Fedora's gcc
    pos$     ./build reference                                     # the first pos reference
    pos-sdk$ POS_TOOLCHAIN_REFERENCE=none POS_POS_REFERENCE=<it> ./build run --new  # by Fedora's gcc
    pos-sdk$ ./build reference
    pos-sdk$ POS_POS_REFERENCE=<it> ./build run --new              # by itself
    pos-sdk$ ./build reference
    pos$     ./build run --new                                     # the stages
    pos$     ./build reference                                     # pos reference of later toolchains

The chain builds with Fedora's tools (see "Build tools"): its first pos
reference has no base stage for extras tools to run on. In a store that
has an extras reference, it runs with `POS_TOOLS=fedora`.

The second toolchain build is the one released: its gcc is built by a POS
gcc of the same sources. The bootstrap glibc is only what the first
toolchains run on; the pos build builds glibc again with the toolchain's
compiler. A toolchain update is a toolchain build with the current
references, stored as the next toolchain reference.

A toolchain built on glibc N runs on glibc N or newer (symbol
versioning), so a toolchain is built on the oldest pos it serves, and a
glibc update in pos needs no toolchain build. pos-sdk pins its pos
reference in its `project` file (`pos-reference <id or release>`), so a
newer pos stored as the default does not raise what the sdk needs; the
pin moves when that is meant. A pos or extras build takes the store's
newest pos reference, which may be newer than its toolchain was built
on; an older glibc is refused. libstdc++ (gcc-runtime) is configured against
the glibc it is built on: new glibc features reach it only with a
toolchain build.

The toolchain runs on glibc only. gcc builds gmp, mpfr and mpc in its tree
(`with-sources`) and links them statically, as it does libstdc++ and libgcc
(`--with-static-standard-libraries`); gcc and binutils use their bundled
zlib and no zstd, and binutils links its own libraries (libbfd,
libopcodes, libctf, libsframe) statically. pos-sdk's gcc recipe fails if a
compiler program needs another library. So a pos build can change any library but glibc, whose ABI is
backward compatible, under the toolchain it builds with: the toolchain
reference's gcc runs on the pos build's glibc as soon as that is built.

The toolchain follows upstream releases, not development: gcc, binutils
and the gmp, mpfr and mpc gcc builds in its tree are release archives (see
"Release archives"), and a new version is a new `archive` and `version`. gcc's
gmp and mpfr are sources of their own, gcc-gmp and gcc-mpfr (`kind
source`, as mpc), apart from core-libs' gmp and mpfr, which coreutils and
gawk use and which follow upstream's development as the rest of pos.

gcc-runtime (libstdc++, libgcc_s) ships in core-libs but is an output of
the gcc build, so the C++ headers a program is compiled with and the
libstdc++ it runs on always come from the same gcc. gcc installs in the
sdk's prefix, `/apps/pos-sdk/<version>`; its recipe moves the runtime's
libraries to `/pos/lib` (gcc-runtime's meta: `prefix /pos`) and points
the names the linker looks up (`<sdk>/lib/libstdc++.so`) at their
sonames there. gcc-runtime also has the run-time libraries of gcc's
other target libraries (the sanitizers, libitm, libquadmath, libssp), as
Arch's gcc-libs: in the sdk's lib the loader would not find them, and a
program built with `-fsanitize=address` would not run.

`util-linux-bootstrap` breaks a cycle with a bootstrap package: it is
util-linux without libsystemd; systemd requires it, and
util-linux requires systemd. util-linux provides its name and obsoletes it,
so once util-linux is built it replaces util-linux-bootstrap everywhere.
Its `build.sh` sources the main recipe after setting `configure_extra`,
which the main recipe appends to its configure arguments, where the later
flag wins (`--without-systemd`).

## Extras
The extras are the packages of the extras pipeline, the pos-extras
project's (`pipeline extras`): the tools builds use and applications, not
part of the OS. An extras build (`run --new` in pos-extras) builds every
package of its project, by default, with the toolchain of a toolchain
reference and on the core-libs and base of a pos reference, as a pos build takes
them before it has built its own; it builds no package of either.
Fedora's compiler builds only from nothing, which the extras are not
part of: an extras build needs a toolchain reference. Its pos reference
is, by default, the store's (see "Reference builds"): the extras link
its libraries. A pos
package outside core-libs and base is not in the pos reference, so an
extras package cannot require it. `./build reference` stores a complete extras
build as an extras reference, the build tools of later builds (see "Build
tools"). The extras
install in `/apps/pos-extras/<version>` (see "Prefix"); pos-extras's
`pos-link` links against that prefix and `/pos`.

The extras link the toolchain reference's gcc-runtime when they are
built, and run on the gcc-runtime of the pos the pos reference was built
as: its pos build's toolchain reference's (a pos reference holds no
gcc-runtime itself). A newer gcc's headers need libstdc++ symbols an older
gcc-runtime lacks (pos-sdk BUILD.md "Run-time coupling"), so an extras
build is refused when that gcc-runtime is older than the toolchain
reference's gcc (the `version` of the gcc-runtime records). Where a
reference records no toolchain reference, either toolchain reference
records no version, or one is not found, it says it cannot check. A gcc update reaches
the extras after a pos build with it is stored as the pos reference
(`./build reference`, or the `pos-reference` setting): until then the
store's pos is one an older gcc built. The build tools are checked the
same way (see "Build tools").

## Build tools
What every step builds with, beyond what a package requires: make, the
autotools, perl, python, git, the shell and the file tools. The `tools`
setting picks them when a build is created (`info`: `tools-reference`):

* an extras reference (see "Reference builds"), by default the store's
  `default-extras`: a pos-extras build or release, and the base stage of
  the build's pos reference. `host-base`
  is left out of the tools image, which keeps the `host-requires` that
  packages and outputs declare. The `build-tools` profile
  (`pos/build-env/packages/build-tools`) lists the tools; its `env.sh`
  puts `<tools prefix>/bin`, `/pos/bin` and `/pos/sbin` on `PATH`, ahead
  of the tools image's, and `pos-link` puts the build's prefix and the sdk
  in front of them. A pos-extras package names the Fedora packages it
  stands for as a build tool in its meta (`replaces-host-rpm`: meson's
  meson, wget2's wget). Of the tools reference's packages the profile
  brings, the tools image leaves those out of recipes' `host-requires`
  and `prepare-requires`, so a step runs the extras' copy, not Fedora's.
  They are read from the reference, so they follow what it has: an older
  one replaces less. Recipes keep the Fedora names for `fedora` tools;
  outputs keep theirs.
* `fedora`: `host-base`'s Fedora packages, installed in the tools image
  (see "Build containers") and a requirement of every package. The
  default where the store has no extras reference or the build has no pos
  reference: the from-nothing chain (see "Toolchain") builds with these.

The tools are resolved after a package's own environment (`env_of`,
`buildsys/resolve.sh`). A tool the environment already provides is not
added. One it does not is the extras reference's (`<name>@tools`), else
the toolchain reference's (`<name>@ref`: gcc-runtime) or the pos
reference's (`<name>@pos`), never this build's, so a tool never
makes a package wait, also not one the run builds (bash in a pos build).
A tool's requirements of /pos packages are the environment's where it
has them, so the tools run on what the build built; those of extras
packages are the extras reference's own, in its prefix: its autoconf runs
its perl. The extras reference's packages stay in their own prefix
(`/apps/pos-extras/<version>-<release>`, see "Prefix"), so their `#!`
lines and runpaths hold; it may not be the build's own prefix, where an
extras build installs its packages.

The C++ tools (gperf, patchelf, ninja, cmake) run on the build's
gcc-runtime: the toolchain reference's, or without one the pos
reference's. A build is refused when that is older than the gcc of the toolchain reference the
extras reference was built with, as an extras build is on its pos
reference (see "Extras"): the tools of a newer gcc need a build with it.

The libraries of the tools are in `/pos` without the package requiring
them, as Fedora's buildroot holds its build group, and a configure
script can find them. `_pkg_linkcheck` (`buildsys/pkg.sh`) fails a
package with an ELF file that links a library of a package only the
tools brought: it requires that package, or keeps the library from being
found. Preparing a source (see "Sources") gets the same tools,
without a package's environment, and its key names the extras reference.

## Build containers
Every step of a build (preparing a source, building a package, making an
output) runs in a podman container of its own, except what an output
does with the host's podman (see "Build outputs"). A package build sees
two things:

* `/usr`: the build's tools image, `localhost/<project>-tools:<id>`, made when the
  build is created (`buildsys/tools.containerfile`). It is the `tools-image`
  setting, Fedora's container image by default, pulled then and pinned by
  digest (`info`: `tools-base`), with the `host-requires` and
  `prepare-requires` of every package and the `host-requires` of every
  output installed by dnf.
  Nothing installs while a build runs, so every step of a run sees the
  same tools whatever order they run in. When a package declares more
  later in the build, the image is made again on the same base
  (`tools-packages` lists what it has). What a step uses from Fedora must
  be declared (`host-base` for every build with Fedora's build tools, see
  "Build tools"): the base image has little more than bash, coreutils and
  dnf.
* `/pos`: the package's resolved environment, composed for this build: the
  staging trees of the POS packages in it (this build's `dest/<name>`, or
  a reference's), and the build tools of an extras reference with what
  they run on, hard-linked into `roots/<package>`, whose top
  directories are mounted read-only: `/pos`, and in an extras build the
  build's prefix under `/apps` too.
  A path has one owner: composing fails when two packages of the
  environment ship the same file or link. The root is removed after the
  build, and kept when it fails, to look at.

A requirement the package does not declare is not there, so the build
fails instead of picking it up from whatever else is installed. Of the
checkout, a step sees only what it uses, at the host's paths: a package
build the recipes (`buildsys`, the trees' `packages`) and its source tree read-only,
and the build's `build`, `dest` and `debug` directories. The source trees
are at `/src/<source>` and the `build` directory at `/build` instead,
whatever the checkout's path and the build ID: compilers write the paths
they build at into debug info, `__FILE__` and libtool archives, and builds
of the same sources should not differ in them. A package build has
`SOURCE_DATE_EPOCH`, the time of its source: the newest member of a
release archive, else the last commit of the source's tree, for the dates
tools write, as in man pages. A step runs as the
caller, with `HOME=/tmp`, `LC_ALL=C` and no network. Preparing has
network, and an output runs as the container's root (the caller outside
it) with network: for dnf and Fedora's kernel, and `pos-fedora`'s Fedora
provides. It sees the recipes (`buildsys`, `outputs`, the stage lists) and the
build directory.

A built package's staging tree carries its metadata in
`<prefix>/lib/pos/packages/<name>/` (`/pos/lib/pos/packages/<name>/` in
pos and pos-sdk; see "Prefix"): `meta` (the package's meta, its
`version`, the build ID, the packages it was built against, the tools
image ID and the reference builds) and `files`. The version is its
source's: a release archive's `version`, or for a synced source the
snapshot prepare names it by, `<ref>-<commit date>-<commit>` from its
`.upstream` (`master-20260217-da607da739fa`); an output has its main
package's (gcc-runtime gcc's). A POS-owned source (pos-integration) has
none. The metadata stays in the stage archives, so
an installed `/pos` records what it contains.

`./build clean` removes the tools image; a later `run` makes it again.

## Reference builds
A reference build is a stored build of another pipeline. There are three
kinds:

* A toolchain reference is a toolchain build: the toolchain packages. Its
  packages are available to the resolver as `<name>@ref`. Where no
  package of the build provides a capability, the reference's copy does,
  if the capability is a stand-in one (one that a package another
  obsoletes provides: the reference's gcc stands in for `gcc-host`), or,
  in a pos build, if no target of the run provides it. A pos build does
  not build the toolchain packages, so they are always the reference's.
* A pos reference is a pos build's core-libs and base stages: glibc, the
  kernel headers and the libraries that link glibc, and the base's tools
  and libraries (see "Base stage"). It must hold what the toolchain
  packages require of pos (glibc, linux-headers). Its packages are
  `<name>@pos`, and provide what no package of the build does in a
  toolchain build, which builds no pos package, or, in a pos build, if no
  target of the run provides it. A run of a single
  package in a new pos build builds only that package, against the pos
  reference's core-libs and base; what it requires outside them must be among
  the targets. In an extras build, as in a toolchain build, a pos
  reference package provides what no package of the build does, and a
  toolchain reference package what no target provides.
* An extras reference is an extras build: the extras packages. A build
  whose `tools` setting names one takes its build tools from it (see
  "Build tools"); its packages are `<name>@tools`.

A reference package's own requirements are those it was built with (its
recorded meta). They are met by this build's packages once built,
otherwise by the references', targets or not: the toolchain reference's
gcc requires glibc, and builds it, running on the pos reference's glibc
until then. Where a package is ready with a reference's copy of a
package the run builds, it waits while another is ready without one: a
package built with the reference's gcc gets the build's glibc, which gcc
requires, once it is built, not the pos reference's. A package this
build installs in another prefix than the reference's copy is not used
for it: the reference's gcc runs the binutils of its own sdk prefix
(`--with-as`), so a pos-sdk build of a new sdk version gives gcc's build
both binutils, the reference's for the compiler and its own to configure
against.

`./build reference [<id>]` (default: the current build) stores a build in
the reference store, the `reference-dir` setting, as
`pos-ref-<kind>-<id>.tar.zst` (`toolchain`, `pos`, `extras`): its
`info` and the staging trees and debug info of what it stores. Of a
toolchain or extras build, which must be complete, that is its packages
and outputs; of a pos build, its core-libs and base packages, which must include
glibc. It marks the build the store's `default-<kind>`, the reference of
that kind of new builds (a store's
`default` from before pos references counts as `default-toolchain`). A
build records its references in `info` (`toolchain-reference`,
`pos-reference`) and restores them from the store into
`work/references/<id>` when they are not there, checking that each is of
its kind; an archive named `pos-ref-<id>.tar.zst`, from before the kinds
had names of their own, is read as either. The store is a directory
outside the checkout, so removing builds never removes a reference.

A published release holds its build's reference archive (see
"Releases"), so a reference not in the store is restored from a release
in the release library that has it, of any project: a pos build can take
its toolchain from a pos-sdk release, and a toolchain build its glibc
from a pos release. The `toolchain-reference` and `pos-reference`
settings take a build ID or a release, `<project>/<release>`
(`pos-sdk/1.0-1.main.20261029-2129`), which names its build; `info`
records the build ID.

A build's pos reference is the `pos-reference` setting, else the
`pos-reference` line of its project's `project` file. A toolchain build
needs one of them: the glibc it builds on is the oldest its toolchain
runs on, which the project decides, not the store. A pos or extras build
otherwise takes the store's `default-pos`, and without one the pos
reference its toolchain reference was built on (`pos-reference` in the
reference's `info`); its glibc may not be older than that one's
(`include/features.h`). A toolchain reference from before pos
references holds glibc as well, which is not used: it was built on that
glibc; a pos build with it takes the store's pos reference or the
setting's.

Comparing a pos build made with a toolchain built from nothing to one
made with a later toolchain (`buildsys/compare-builds.sh`: the files of
each package and the libraries every ELF file links against) shows what
the build environment leaked into a package.

## Build setup
`pkg_setup` has no build strategy of its own. A package that changes how
others are built has an `env.sh`, and `pkg_setup` sources the `env.sh` of
every package in the resolved requirements. What a build gets therefore
follows from what it requires, never from what is found on disk:

* `gcc/env.sh`: the POS compiler, `$sdk_prefix/bin/gcc`, `g++` and `ld`,
  and binutils' `ar`, `ranlib` and `nm`, which write archives with zero
  dates; pos-sdk's recipe, installed with gcc (see "Engine").
* `host-toolchain/env.sh` and `gcc-host/env.sh`: the Fedora compiler,
  searching `/pos` ahead of `/usr` (`gcc-host`, standing in for gcc).
* `pos-link/env.sh`: link against `/pos` with the build's compiler.

`pos-link` and `gcc-host` are profiles (`kind profile`): nothing is built
or installed, they only carry the setup and its requirements. Recipes
build-require `gcc` and `pos-link`, which requires `gcc`. glibc requires
only the compiler and linux-headers (see "Core libs stage");
linux-headers only `host-gcc`, for the one program its build runs.

Requirements are what a build sees, but configure scripts also find what
they were not asked to. gcc's run-time requirements (glibc, gcc-runtime,
binutils, linux-headers) are in every build that uses it, and gcc-host's
Fedora compiler falls back to the tools image's `/usr`. A package that
links a library must require it.

## Build flags
`pkg_setup` sets the flags every package is built with (`pkg_flags`), as
Fedora's and Arch's package builds do, before the `env.sh` files add to
them:

* `CFLAGS`: `-O2 -g -pipe`, and the hardening `-fexceptions
  -Wp,-D_FORTIFY_SOURCE=3 -fstack-clash-protection -fcf-protection`, with
  frame pointers (`-fno-omit-frame-pointer -mno-omit-leaf-frame-pointer`)
  for profilers. `CXXFLAGS` adds `-D_GLIBCXX_ASSERTIONS`.
* `LDFLAGS`: `-Wl,-O1 -Wl,--as-needed -Wl,-z,relro -Wl,-z,now
  -Wl,--build-id=sha1`.
* PIE and `-fstack-protector-strong` are the POS compiler's defaults
  (`--enable-default-pie --enable-default-ssp`), and it gives every link
  a build ID (`--enable-linker-build-id`). Fedora's compiler, used in a
  build without a toolchain reference, does both through its own
  defaults.

meson builds use `--buildtype=plain` and cmake builds
`-DCMAKE_BUILD_TYPE=None`, so these flags are the only ones; meson's
`release` would have added `-O3` and no debug info. Warnings are not made
errors (no `-Werror=format-security`): POS builds upstream's development
branches.

glibc and gcc keep
only `-O2 -g -pipe` (`pos_optflags`). glibc has its own hardening options
and builds parts of itself without the stack protector; gcc derives the
flags of its target libraries (libgcc, libstdc++) from `CFLAGS`. glibc
also gets no `LDFLAGS`; it links itself by its own rules.

CET (`-fcf-protection`) only takes effect when every object of a link
has it, including glibc's `crt1.o` and `crti.o` and gcc's `crtbegin*.o`.
glibc is configured `--enable-cet` (its default follows the compiler's,
which is off); gcc enables it in its target libraries by itself.

## Debug info
`pkg_finish` strips what a package installs and keeps the debug info
separately (`pkg_strip`), as Fedora's debuginfo packages do. Each ELF
program and shared library's debug info is copied to
`work/builds/<id>/debug/<package>/pos/lib/debug/.build-id/<xx>/<rest>.debug`,
named by its build ID, where gdb and debuginfod look for it; the file in
`dest/<package>` is then stripped. The debug files' DWARF sections are
compressed with zlib, as Fedora's are: about 60% less unpacked, though
the zstd archives that hold them come out slightly larger. zstd sections
would need the toolchain's binutils built with zstd. The loader keeps its symbol table
(valgrind needs it), static libraries lose only their debug info, and
object files (`crt*.o`) are left as they are. A file without a build ID is
stripped with a warning in the log. Set-uid bits, modes and hard links are
kept.

The debug trees are not part of build roots. Each stage's is
archived next to it as `pos-debug-<stage>-<stem>.tar.zst`, which extracts
on top of the stage into `/pos/lib/debug`, and the RPM outputs make it the
`pos-debuginfo` package. gdb looks in `/usr/lib/debug` unless told
otherwise, and reads the directory before it loads the program:

    $ gdb -iex 'set debug-file-directory /usr/lib/debug:/pos/lib/debug' /pos/bin/bash

# Prefix
`/pos` is the prefix for everything POS ships: the base system, and optional
components such as the SDK. It stays read-only for the whole lifetime of an
installation. An update replaces the tree. Programs, libraries, headers, and
shipped data that POS provides install there. Programs in `/pos` have no
dependencies outside the prefix.

Third-party applications install in separate hierarchy. A machine can keep `/usr` for that, or any other prefix.

A project's packages install in its prefix: the `prefix` line of its
`project` file, `/pos` without one. pos installs in `/pos`, pos-sdk in
`/apps/pos-sdk/<version>` and pos-extras in `/apps/pos-extras/<version>-<release>`. `<version>` is `<product
version>.<revision>` of `VERSION` (1.0.0): it stays the same while
developing, so builds of the same sources stay comparable (the prefix is
compiled into programs), and changes with a service release. `<release>`
is the build's product release (see "Build numbers"),
`<branch>.<timestamp>` while developing: every build has a prefix of its
own, so a build can take the build tools of another (see "Build tools"),
and two builds of the same sources differ in it. A new
build records its prefix in `info` (`prefix`), and a reference build's
packages are found in the prefix its `info` names (`/pos` for builds
from before prefixes). A package can install in `/pos` instead (meta
`prefix /pos`; its record is there too). The recipes have it as
`$prefix`; `$pos_prefix` is `/pos`, what every build links against, and
`$sdk_prefix` the sdk the build compiles with: its toolchain
reference's prefix (`/pos/sdk` for toolchains from before prefixes),
also in a pos-sdk build, which installs the new sdk in `$prefix`. A
staging tree is a root holding the prefix (`dest/<name>/pos`,
`dest/<name>/apps/pos-extras/1.0.0`).

The POS loader finds only `/pos/lib` (see "Library directory"). A
program or library in another prefix that links libraries of that
prefix gets a runpath to them relative to itself: `$ORIGIN/../lib` from
`bin`. `_pkg_runpath` (`buildsys/pkg.sh`) sets it after install with
patchelf, from `host-base` or `build-tools` (see "Build tools"), so
`$ORIGIN` need not survive configure and make quoting. It looks in
`<prefix>/lib` and in the runpath entries in the prefix a build tool set
(libtool's absolute libdir), and drops entries outside the prefix (build
directories). A program then loads the libraries of the tree it comes
from, wherever that tree is and whichever versions sit beside it, as
apps bundle theirs. `/pos` keeps no runpath.

The sdk, the toolchain (see "SDK"), is not part of pos: pos-sdk installs
it in `/apps/pos-sdk/<version>`, the whole prefix its own (`bin`, `lib`,
`libexec`, `include`, `share`); only gcc-runtime, which it builds, is in
`/pos/lib`. Nothing in the sdk is written at run time. The loader does
not search its `lib`: the sdk's programs link only glibc and gcc-runtime,
and link anything else statically. pos names no sdk path: the search
paths below, an imported image's `PATH` and pos-fedora's `/usr/bin` links
are pos's. Software installed outside `/pos` goes on `PATH` when it is
installed on a machine, by a drop-in of `/etc/profile.d`, which
pos-integration's `/etc/profile` reads.

Configuration and mutable data stay outside the prefix:

* `/etc` is local configuration.
* `/var` is variable data.
* `/run` is runtime state.

Every package is configured with `--sysconfdir=/etc` and, where it applies,
`--localstatedir=/var` (`$sysconfdir` and `$localstatedir` in `buildsys/pkg.sh`).
There is no `/pos/etc` or `/pos/var`. glibc only rewrites those paths to
`/etc` and `/var` when its prefix is `/usr`, so with `--prefix=/pos` the
flags have to be passed explicitly. Files a package installs into `etc/` or
`var/` at build time are shipped defaults, so `pkg_finish` moves them to
`/pos/share/factory`, and write a tmpfiles.d file of the package,
`/pos/lib/tmpfiles.d/factory-<package>.conf`, with a `C` line for each:
`systemd-tmpfiles` copies a file into place where it is missing, at every
boot and when an image is made (`fs_factory`). glibc's nss_db helper is one of them: it
is installed as `/var/db/Makefile` and generates the `.db` files there from
`/etc`. A path the package's own tmpfiles.d files already create
(systemd's `credstore.conf` and `20-systemd-*.conf` links) gets no line,
as tmpfiles would warn about the duplicate. Packages that have a separate vendor directory (pam's `vendordir`)
ship their defaults there instead. `DESTDIR` is only the staging directory
under `work/` used at install time. It is not part of the running system.

Packages assume `/usr` in places `--prefix` does not reach. Two ways to
handle it: a configure option that moves the path (preferred, it keeps the
binary self-contained), or a symlink from the hardcoded path back into
`/pos`. Symlinks live in the root filesystem, outside any package, so they
are part of the root layout an image stage creates; a package never installs
outside `/pos` (`buildsys/build.sh` warns on it).

* systemd: units, generators and `systemd-*` binaries are searched relative
  to `--prefix`. The programs it execs default to `/usr/bin` and `/usr/sbin`
  and are moved with the `*-path` options (`-Dkmod-path=/pos/bin/kmod`,
  `-Dmount-path`, `-Dsulogin-path`, ...). Its `pam.d` files go to
  `-Dpamconfdir=/pos/share/pam/pam.d`, the vendor directory POS pam reads;
  pam's other fallback, `/usr/lib/pam.d`, is hardcoded.
* systemd-tmpfiles: a `C` line without a source argument copies from
  `/usr/share/factory/`. That path is hardcoded. POS's lines give the
  source explicitly (`C /etc/foo - - - - /pos/share/factory/etc/foo`); a
  root layout can also have `/usr/share/factory -> /pos/share/factory`,
  for third-party tmpfiles lines.
* os-release: `/etc/os-release` and `/usr/lib/os-release` are where the
  os-release specification and systemd (PID 1, hostnamed, nspawn, image
  dissection) look. POS's is `/pos/lib/os-release` (pos-integration);
  `/usr/lib/os-release` links to it, from an image's layout or from
  pos-fedora, and `/etc/os-release` to that, as systemd's tmpfiles.d
  `etc.conf` makes it.
* Shebangs and the kernel: `#!/bin/sh`, `#!/bin/bash`, `#!/usr/bin/env`,
  `/sbin/init`, and `/lib64/ld-linux-x86-64.so.2` for third-party binaries
  are the same class. Which of these the root layout provides as symlinks
  into `/pos` is decided per image (see "Images"), and for a machine it
  interacts with keeping its own `/usr`. The container image has them all.
* systemd's drop-in directories (`tmpfiles.d`, `sysusers.d`, `sysctl.d`,
  `modules-load.d`, `binfmt.d`, `udev/rules.d`, ...) and kernel-install's
  plugins are searched in `/etc`, `/run`, `/usr/local/lib` and `/usr/lib`.
  Its prepare recipe adds `/pos/lib` before `/usr/lib`, as units have the
  prefix before `/usr/lib`, so packages outside POS (Fedora's on a
  `pos-fedora` system, a kernel) are still read.
* kmod: `-Ddistconfdir=/pos/lib` for `modprobe.d`/`depmod.d`. Modules are
  found in `/usr/lib/modules`, where kernel packages install them: POS boots
  kernels other projects build. A disk's `/usr/lib/modules` links to
  `/var/lib/pos/kernel/modules` (see "Kernels"). The kernel loads modules on demand with
  the modprobe its build names (`/usr/bin/modprobe` in Fedora's); kmod's
  `sysctl.d/50-kmod.conf` sets `kernel.modprobe` to `/pos/sbin/modprobe`.
* systemd: programs a unit names without a path, and the `PATH` of
  services and user sessions, are looked up in `/usr/local` and `/usr`, with
  `/pos/sbin:/pos/bin` appended (`-Dextra-exec-search-path`).
  sudo's `secure_path`, login's (shadow's `login.defs`) and sshd's are the
  same list.
* util-linux: `--enable-fs-paths-default=/pos/sbin` for mount helpers.
* shadow: `--enable-vendordir=/pos/share/factory/etc`, so login.defs is found
  before `/etc/login.defs` has been created. pam's vendordir
  (`/pos/share/pam`) could move to the same tree for consistency.
* qemu-ga: poweroff, halt, reboot, shutdown and hwclock are run by their
  `/sbin` paths, string constants with no configure option;
  `pos/system/packages/qemu/prepare.sh` points them at `/pos/sbin`.
* logrotate: `--with-compress-command=/pos/bin/gzip`. Tool paths found by
  configure are the general case: a build container finds `/usr/bin`
  tools and records those unless told otherwise (man-db's recipe shows the
  `--with-nroff=/pos/bin/nroff` pattern).
* systemd unit, tmpfiles and sysusers directories for packages built before
  systemd (util-linux): given explicitly as `/pos/lib/systemd/system`,
  `/pos/lib/tmpfiles.d`, `/pos/lib/sysusers.d`.

## Library directory
`/pos/lib` is the only library directory: the native x86-64 libraries, the
loader `/pos/lib/ld-linux-x86-64.so.2`, and the architecture-independent
trees (`lib/systemd`, `lib/pos`). There is no `/pos/lib64`
and no multilib. This is the Arch and LFS layout, not Fedora's, where
`lib64` holds the 64-bit libraries and `lib` the 32-bit ones and the
architecture-independent files.

The upstream defaults assume Fedora's layout in a few places, which the
recipes override:

* gcc: `t-linux64` names `../lib64` for `-m64`; the recipe makes it
  `../lib`, and gcc is `--disable-multilib`.
* glibc: the x86-64 `ldd-rewrite.sed` turns the loader list into the
  `lib64`/`lib`/`libx32` set; `ldd-rewrite-script = no` in configparms keeps
  `RTLDLIST` at the installed loader.
* meson, cmake's GNUInstallDirs and Fedora's gcc see the build
  container's `/usr/lib64` and choose `lib64`; recipes built with them set libdir to
  `/pos/lib`. gcc is `--disable-libcc1`: libcc1 installs into the
  building compiler's multilib directory, which Fedora's g++ answers with
  `../lib64`.

`pkg_record` stops a build that installs into `pos/lib64`, `pos/lib32` or
`pos/libx32`; the POS loader would not find libraries there.

32-bit binaries are not built. 32-bit programs are applications 
(Steam, older Wine), outside the base system,
and can run from an install root of another distribution that ships
32-bit libraries. If POS ever ships an i686 compat set, it goes in
`/pos/lib32` with its loader at `/pos/lib32/ld-linux.so.2`; gcc then
gets multilib with `m64=../lib m32=../lib32`, and the glibc recipe writes
ldd's `RTLDLIST` itself.

# Set-uid programs
The staging install runs unprivileged, so `make install` cannot chown or set
set-uid bits (util-linux `--disable-makeinstall-chown --disable-makeinstall-setuid`,
sudo `install_uid=$(id -u)`). Recipes call `pkg_setuid` on the programs that
need it (su, mount, umount, chfn, chsh, passwd, chage, gpasswd, newgrp,
sudo, crontab, dbus-daemon-launch-helper); that sets mode 4755 in
the staging tree. `assemble.sh` records owner 0:0 in the archive, so
extracting it as root produces root-owned set-uid files. Anything that
installs the tree has to preserve modes (`tar -x` as root, or `cp -a`, not
`cp -r`; unprivileged `tar -x` needs `-p`).

# Core libs stage
Each package stages into `work/builds/<id>/dest/<name>` with `--prefix=/pos`
(the project's prefix; see "Prefix").

With the sdk compiler, packages use `gcc`, `g++` and `ld` of
`$sdk_prefix/bin`, whose defaults already search `/pos/include` and `/pos/lib`,
and `pos-link` adds only
`-L/pos/lib` and `PKG_CONFIG_LIBDIR` (`/pos/lib/pkgconfig` and, for
the architecture-independent `systemd.pc`, `udev.pc` and `kmod.pc`,
`/pos/share/pkgconfig`). No rpath: the POS loader finds
`/pos/lib` through its own cache or its default search path (below).
`/pos/include` must not be named again with `-isystem` or
`CPLUS_INCLUDE_PATH`. That moves it in front of the libstdc++ directories,
gcc drops the later duplicate, and libstdc++'s `#include_next <stdlib.h>`
finds nothing after itself (ncurses then falls back to `<iostream.h>`).

A build without a toolchain reference is built by the host toolchain.
Only there does `gcc-host` add `-isystem /pos/include`,
`C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH`, and `LIBRARY_PATH` to put `/pos`
ahead of the host's `/usr`.

The POS loader and ldconfig use `/etc/pos/ld.so.cache` and
`/etc/pos/ld.so.conf`, not `/etc/ld.so.cache` and `/etc/ld.so.conf`. Those
belong to the loader of whatever else is on the machine: a `/usr` the
machine keeps, or Fedora in a build container. One cache listing both sets of
libraries makes each loader pick up the other's libc; in a toolbox the POS
loader found Fedora's `/lib64/libc.so.6` and every program without an rpath
crashed (gcc's libatomic configure runs one). The glibc recipe sets
`LD_SO_CACHE` and `LD_SO_CONF` in `configparms`. With no POS cache, as in a
build container, the loader searches `/pos/lib`. glibc ships
`/etc/pos/ld.so.conf` (`/pos/lib`) as a factory default, so ldconfig can
write the cache next to it; pos-fedora's adds `/usr/lib64`. dracut's
library lookup (dracut-install, and the cache it makes in the initramfs)
is changed by its recipe to read `/etc/pos/ld.so.conf` and search
`/pos/lib`, as the POS loader does.

Binaries in `/pos` carry no rpath (other prefixes: see "Prefix"). The loader searches the binary's RPATH/RUNPATH,
then `LD_LIBRARY_PATH`, then its cache, then its default directory
(`/pos/lib`). The POS cache is built from `/pos/lib` and
`/etc/pos/ld.so.conf`, so it gives the same answer as the default; an rpath
would only repeat it. Library lookup is decided in one place: the cache and
`/etc/pos/ld.so.conf`.

glibc is built with the toolchain reference's gcc, which runs on the pos reference's glibc. This is the same arrangement
as Fedora: the gcc in `/usr` was linked against the installed libc, and it
compiles the glibc that will replace it. The compiler runs on the old libc.
The new one is a build output. glibc passes `-nostdlib -nostartfiles` and
names the build-tree `libc.so` and `ld.so` on the link line, then appends
its own `-Wl,-dynamic-linker=/pos/lib/ld-linux-x86-64.so.2`.

The extra search path other packages get stays off for this build: glibc
requires `gcc`, not `pos-link`. With `gcc-host`, in the bootstrap pos
build, it does get `/pos` in its search; there `/pos` holds the kernel
headers only, which glibc wants.
`C_INCLUDE_PATH` and `LIBRARY_PATH` are not disabled by `-nostdinc` or
`-nostdlib`, and the `/pos` link flags are not ones glibc puts on its own
binaries. Fedora gets the header isolation from `--with-headers`, which
turns on `-nostdinc` and adds only the kernel headers. Our recipe does not
pass that, because the kernel headers and the installed glibc headers share
`/pos/include`.

In a build without a toolchain reference, the host gcc is still
visible and keeps `/usr/include` and `/usr/lib64` in its default search
after `/pos`. A configure check for a library that is not in `/pos` yet
then finds the tools image's copy, and the binary fails to load because the
POS loader searches only `/pos/lib`. A build that dies with exit 127 while
running its own freshly built program is this. Check with
`objdump -p <binary> | grep NEEDED`.

glibc installs C.UTF-8 as `/pos/lib/locale/C.utf8` (Fedora's
glibc-minimal-langpack has the same): programs that need a UTF-8 locale
fall back to it (tmux), and containers set it. The other UTF-8 locales of
glibc's `localedata/SUPPORTED` are compiled into one archive,
`/pos/lib/locale/locale-archive`, so any language works as it is;
the legacy character sets (ISO-8859-*, EUC-*, ...) are not built. glibc
reads compiled locales only from its own prefix, not Fedora's
`/usr/lib/locale`.

linux-headers, the kernel UAPI headers, are in this stage: glibc's
headers include them (`errno.h` includes `<linux/errno.h>`), and glibc
builds with them. They are needed only while compiling; nothing loads
them at run time. The toolchain builds on them as on glibc, from a pos
reference.

linux-headers is built from `pos/core-libs/src/linux`, mainline's `master`, synced as the
subset of the kernel tree that `make headers_install` needs: the top-level
`Makefile`, `scripts/`, `include/uapi/`, x86's `Makefile`, `include/uapi/`
and system call tables, and the licenses. The subset was checked by
comparing its installed headers with those of the whole tree. The recipe
builds out of tree (`O=`), so the source stays as committed. UAPI headers
are compatible with older kernels, so headers from mainline work on the
kernel a machine runs. A kernel package needs the whole tree, a source of
its own.

gmp and mpfr are in this stage. coreutils `expr` and `factor`, and gawk
`-M`, link them at run time. gmp `--enable-cxx` needs libstdc++, from the
toolchain reference's gcc-runtime. The compiler has its own static copies (see
"Toolchain").

`ca-certificates` installs the Mozilla trusted root certificates as
`/pos/share/ca-certificates/ca-bundle.crt` and provides `/etc/ssl/cert.pem` and
`/etc/ssl/certs/ca-certificates.crt` via the factory tree for OpenSSL and standard
tools. `tzdata` installs the IANA time zone database into `/pos/share/zoneinfo`
and the `zic`/`zdump` utilities.

`run` assembles each stage it was given into one archive,
`work/builds/<id>/pos-<stage>-<stem>.tar.zst`, with a top-level `pos/`
directory. The merged tree is left at `work/builds/<id>/assemble/<stage>/pos`.

# Build outputs
An output is what a build makes of its assembled stages: an image, a disk,
RPM packages. `outputs/<output>/` holds `meta`, which declares what it is
made from, and `output.sh`, its recipe (format in `buildsys/outputs.sh`):

    requires core-libs base system
    host-requires rpm-build

`requires` names stages and other outputs: an output is made from the
stages of the build once they are assembled, and from what the outputs it
requires made (container-fs-dnf from the RPM packages of rpm-pos and
rpm-pos-fedora; fedora-toolbox from container-fs-dnf).
`host-requires` are Fedora packages its steps need in the tools image.

| output | requires | makes |
| --- | --- | --- |
| `container-fs` | core-libs, base, system | `pos-container-fs-<stem>.tar.zst` |
| `stage-images` | core-libs, base, system, network, container, storage | `pos-<stage>-<stem>.raw` and `.requires` of network, container and storage |
| `vm-disk` | core-libs, base, system, stage-images | `pos-vm-disk-<stem>.qcow2` |
| `rpm-pos` | core-libs, base, system | `rpm/pos`, `rpm/pos-debuginfo` |
| `rpm-pos-fedora` | core-libs, base, system | `rpm/pos-fedora` |
| `container-fs-dnf` | the rpm-pos outputs | `pos-container-fs-dnf-<stem>.tar.zst` |
| `vm-disk-dnf` | the rpm-pos outputs | `pos-vm-disk-dnf-<stem>.qcow2` |
| `fedora-toolbox` | container-fs-dnf | `localhost/pos-fedora-toolbox` in podman |

`run` makes every output whose stages it assembled, directly or through
the outputs it requires, so a plain `run` makes them all. Each starts as
soon as what it requires is made, at the same time as the others that are
ready, and logs to `logs/output-<output>.log`; after a failure no more
start. `./build output [<output>...]` makes outputs of the current build
again (default: every output its assembled stages can make), from what
the build already has.

A recipe defines `output()`, which runs in a container of the build's
tools image as the container's root, with network (see "Build
containers"), and `output_host()`, which runs on the host after it, for
what needs the host's podman. Both call the functions of
`buildsys/output-plugins.d`: `fs.sh` makes a root tree and archives it,
`disk.sh` makes a disk of it and checks the disk, `rpm.sh` makes RPM
packages, `sysext.sh` makes stage images (see "Stage images") and
`podman.sh` builds and imports podman images. A recipe may
use another output's files: vm-disk-dnf takes vm-disk's `root/` and
`repart.d`.

## Images
An image is a root filesystem with POS installed, made by `fs.sh` in the
output's scratch directory, `output/<output>/root` of the build, and
archived as `pos-<output>-<stem>.tar.zst` (`fs_archive`) or made into a
disk (see "Disks"). `fs_stages` extracts the stage archives the output
requires into `/pos`, in order; `fs_layout` makes the root layout around
`/pos` from `outputs/<output>/layout`: directories with their modes, and
the symlinks into `/pos` for the paths in "Prefix". `fs_copy` copies the
files of a directory in, such as `outputs/vm-disk/root` (`/etc/kernel`,
the network).

`fs_factory` and `fs_sysusers` fill what a first boot would: the factory
tree's `C` lines are applied to `/etc` and `/var` by the image's own
`systemd-tmpfiles`, and `/etc/passwd`, `group`, `shadow` and `gshadow` are
created by POS `systemd-sysusers --root` from `/pos/lib/sysusers.d`. That
runs through the image's own loader, `pos/lib/ld-linux-x86-64.so.2
--library-path ...`, so `/pos` need not be installed where it runs.
Everything is owned by root in the archive. Group write, which build trees
pick up from the build directory, is removed except on sticky directories.

`container-fs` is core-libs, base and system, for `podman import` or
`docker import`. It has no `/etc/pos/ld.so.cache`; the loader searches
`/pos/lib`. Programs are in `/pos/bin` and `/pos/sbin`, which are not in
a container engine's default `PATH`, so the import sets it:

    $ podman import \
        --change 'ENV PATH=/pos/bin:/pos/sbin:/usr/local/bin:/usr/bin' \
        --change 'CMD ["/bin/bash"]' \
        work/builds/<id>/pos-container-fs-<stem>.tar.zst pos:<id>

`devtools/import-image.sh [-o <output>] [<id>]` does that, and tags the
image with the build's product version too (`pos:1.0`), the tag to make
containers from: it moves to whichever build of that version was imported last. An
output's name in podman (`tag`) and whether POS's programs come first in
`PATH` (`path-priority pos`) are in its `meta`. For an image made with
podman (see "Images made with podman"), which is in podman already, it
only sets the version tag.

`vm-disk` is a bootable POS system without an RPM layer: core-libs, base
and system, Fedora's kernel and a disk (see "Disks"). `fs_kernel` installs
the kernel of a pos-kernel channel (`fedora`) as a running system would
(see "Kernels"): it downloads the channel's packages from Fedora's
repositories with dnf, and the tree's `pos-kernel import` unpacks them
into its archive and adds the boot entry with POS's kernel-install, whose
plugins run depmod, POS's dracut, which makes the initramfs, and write
the entry (`root/etc/kernel`). `/lib/modules` links to `/usr/lib/modules`,
the path kernel packages and dracut use, and that to
`/var/lib/pos/kernel/modules`.

## Images made with dnf
`fs_dnf` makes the tree with `dnf --installroot`: POS as the base of an
RPM system (see "RPM packages"). A package named `pos` or `pos-*` is the
build's own RPM file (`pos`, `pos-fedora` and their debuginfo),
anything else comes from Fedora's repositories. Next to the output's
artifact, `pos-<output>-<stem>.packages` lists the packages installed. The
tree's files belong to users the packages create, which only the
container's root can remove: the scratch directory is removed in the
container when the output is made.

The root layout comes from Fedora's `filesystem` and `setup` packages and
pos-fedora's links; users and groups are created by rpm from the packages'
sysusers definitions. No package creates `/tmp` (on Fedora,
systemd-tmpfiles and the image builders do), so fs_dnf makes it. The
recipes apply the factory tree's `C` lines too (`fs_factory`), as a boot
would: dnf installs none of POS's files outside `/pos`. `/etc/os-release`
is POS's (pos-fedora's links). Files copied in before (`fs_copy`) are
there for the packages' scriptlets to read.

The scriptlets run in the root as on a running system: dnf runs with
`/proc`, `/sys` and `/dev` mounted in the root, and a file system of its
own at `/boot`, as the ESP is when the system runs. The mounts are in a
mount namespace of the step's container (which runs as the container's
root, allowed to mount there) and are gone when dnf is done; what was
written to `/boot` is kept in the tree.

`container-fs-dnf` is `pos`, `pos-fedora` and `dnf`: a
container with POS as its base in which `dnf install` adds Fedora
packages, which use POS for what it replaces:

    $ devtools/import-image.sh -o container-fs-dnf
    $ podman run --rm -it pos-dnf
    # dnf install htop

`vm-disk-dnf` is container-fs-dnf's packages and Fedora's kernel
(`kernel-core`, `kernel-modules`): a bootable system. POS boots kernels
other projects build; Fedora's kernel package installs as on Fedora. Its
scriptlet runs POS's kernel-install (vm-disk's `root/etc/kernel`: Type #1
boot loader entries, the kernel command line), whose plugins are POS's
(depmod, the loader entry, and dracut's, which makes the initramfs from
POS's systemd, udev and libraries). The kernel, initramfs and entry are in
`/boot`. The root has `/usr/lib/modules` as a link to
`/var/lib/pos/kernel/modules` before dnf installs (its `layout`): rpm keeps
a link where a package has a directory, so the kernel package's modules
go there, out of `/usr`, and `rpm -V` is clean.

## Disks
`disk_make` makes the tree a disk, `pos-<output>-<stem>.qcow2`: the
image's own systemd-boot is installed into `/boot` (POS `bootctl
install`), then `systemd-repart` makes the partitions of a `repart.d` and
fills them from the tree, without loop devices or privileges. The
partitions have the discoverable partition types, so systemd finds them
by type: no fstab and no `root=` on the kernel command line. vm-disk's
`repart.d`, which vm-disk-dnf uses too, is a 1G ESP (vfat) with `/boot`'s
contents, mounted at `/boot`, and an 8G root (ext4) with the rest. The
disk is a compressed qcow2 image (systemd-repart's raw disk converted with
`qemu-img`), which qemu and libvirt boot as it is; how to run it is up to
whoever uses it. `qemu-img convert -O raw` gives a raw disk.

The root grows to the disk it is on. vm-disk's `root/etc/repart.d` has a
definition of the root partition without a maximum size, so
systemd-repart, at every boot, grows it into the free space after it, and
systemd-growfs-root grows its file system (GPT flag 59, which repart sets
on the root by default). A copy made bigger before its first boot
(`qemu-img resize <copy> 40G`), or later, is used whole after the next
boot. vm.sh's overlay is 4G bigger than the disk, and smoke.sh checks that
the root fills it.

The disk boots with UEFI firmware only: it has no BIOS boot code, so a
BIOS (SeaBIOS, libvirt's default) stops at "Booting from Hard Disk". In
libvirt, choose UEFI without Secure Boot (virt-manager: customize before
install, Firmware `OVMF_CODE.fd`, not a `secboot` one; virt-install:
`--boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no`),
since systemd-boot and the kernels are not signed. Libvirt writes to the
disk it is given; give it a copy.

The kernel command line (vm-disk's `root/etc/kernel/cmdline`) is
`console=ttyS0 console=tty0`. Kernel messages show on both; the last one,
the display, is `/dev/console`, where systemd shows its status and the
first boot's questions. Each has a login prompt: getty@tty1 on the display,
and a serial getty that systemd's getty generator starts for the serial
console. On the first boot systemd-firstboot asks for the timezone (UTC is
filled in) and the root password, which is how root gets one; locale and
keymap are not asked, as systemd-firstboot asks only where there is a
choice. Systemd credentials answer the questions instead
(`passwd.hashed-password.root`, `firstboot.timezone`, see
systemd-firstboot(1)); libvirt passes them as SMBIOS type 11 strings, as
vm.sh does.

`devtools/vm.sh [-o <output>] [<id>]` boots a disk in qemu with KVM and
UEFI firmware, in a container of `localhost/pos-vm` (Fedora with qemu
and OVMF, made when missing), on the serial console of the terminal
(Ctrl-a x quits), which it makes `/dev/console` by appending
`console=ttyS0` and `systemd.firstboot=no` to the command line. The disk
is not changed: the VM writes to an overlay that is gone when it stops. Root is logged in on the console by a getty
drop-in passed as a systemd credential, so no password is set. The VM
has qemu's user mode network: dnf works inside.

`vm.sh -c <script>` runs a script in the VM instead, without a console:
the script and a unit that runs it go in as credentials (the unit as
`systemd.extra-unit`, pulled in by `systemd.wants` on the command line),
it runs as root once the boot transaction is done, writes to a second
serial port that vm.sh prints, and the VM powers off. vm.sh exits with the
script's status; the console goes to `logs/vm-<output>.log` of the build.
`devtools/smoke.sh` is the check of a booted image: system state, failed
units, module loading in the initrd and after, unit file modes, the login
prompt on tty1, the QEMU guest agent, network and dnf, the PAM services
and sudo. Its status is the number of failed checks. `disk_check` runs it in `output_host()` (see "Build numbers").

## Kernels
POS boots kernels other projects build. `pos-kernel` (`/pos/sbin`,
pos-integration) installs and updates them on a running system, from
kernel channels: `fedora` (Fedora's kernel, the updates of the Fedora
release POS's build is made with), `mainline` and `stable` (kernel.org's
trees built with Fedora's configuration by Fedora's kernel-vanilla
project, COPR `@kernel-vanilla`, Thorsten Leemhuis'), and `linus`,
kernel.org's mainline release built on the machine. README.md has the
commands.

* A channel is a file in `/pos/lib/pos/kernel/channels`
  (`/etc/pos/kernel/channels` replaces one): `description`, `format`,
  and the format's keys. The format is a plugin in
  `/pos/lib/pos/kernel/formats` with `format_available` (the kernel
  versions the channel has), `format_download` and `format_unpack`.
  `rpm` reads rpm-md repositories (`repo` base URLs, `metalink` URLs of
  Fedora's mirror lists, the first https mirror that answers) for the
  channel's `packages`, checks each package against the repository's
  SHA-256, and unpacks it without rpm: the payload follows the lead and
  two headers whose sizes are in the file, and is a compressed cpio
  archive (xz, zstd or gzip). Only the packages' `/lib/modules/<kver>`
  is kept (vmlinuz, config, System.map, modules); no scriptlet runs.
  Signatures are not checked: trust is the repository's https.
* `build` builds a kernel on the machine from kernel.org's tarball of a
  release (`releases.json`, `moniker`): the configuration of the newest
  kernel of the `config-from` channel (or the running kernel's), the
  channel's `config` lines (`scripts/config`: no BTF, no debug info, no
  module signing, no `-Werror`), `localversion` (`-local`), then
  `localyesconfig` with the modules seen loaded: they are built in, other
  modules left out, except under `keep` (`LMC_KEEP`, all of a directory's
  modules: a driver that loads firmware when it starts needs to be a
  module, started once the root with the firmware is there; none by
  default). `make` names pos-sdk's compiler, the selected version's
  (`CC=/apps/pos-sdk/current/bin/gcc`), not another in the `PATH`.
  The modules seen loaded are a list,
  `/var/lib/pos/kernel/modules-seen`, that `pos-kernel record-modules`
  adds `/proc/modules` to, at every boot and shutdown
  (`pos-kernel-modules.service`, enabled by POS's preset), and before
  every update: it holds what the machine used while it ran a hosted
  kernel. With no list, the configuration is built whole.
* A channel's `requires` are the commands its format runs. pos-kernel
  checks them before it enables or updates the channel, and names the
  missing ones; when the compiler is, it says to install pos-sdk.
  `linus` needs pos-sdk and make, flex, bison, bc and perl,
  which POS does not package yet.
* The archive, `/var/lib/pos/kernel/archive/<channel>/<kver>`, holds each
  kernel's modules directory. For each channel the system boots, its
  newest kernel has a boot entry and the one before it a fallback entry;
  the running kernel keeps its entry. A kernel with an entry is linked
  from `/var/lib/pos/kernel/modules/<kver>`, which kmod, the kernel's
  module loading and dracut find as `/usr/lib/modules/<kver>`: the disk's
  layout links `/usr/lib/modules` there, so modules are out of `/usr`.
  kernel-install adds and removes the entries (depmod writes into the
  archive). The archive keeps `kernel.keep` kernels of a channel (3).
  A disabled channel keeps its kernels without entries until it is
  removed.
* The global system preferences (`pos-preferences`, pos-integration):
  `<tool>.<name> <value>` lines, POS's defaults in
  `/pos/lib/pos/preferences`, the administrator's in `/etc/pos/preferences`.
  pos-kernel's are `kernel.channels` (the channels the system boots, at
  least one; `fedora`), `kernel.default` (the channel whose newest kernel
  boots by default; `fedora`) and `kernel.keep`.
* The default entry is `default <entry>` in `/boot/loader/loader.conf`,
  rewritten on each change; without one systemd-boot boots the newest
  entry. bootctl's `install` keeps an existing loader.conf.
* Downloading needs curl, which is in the base stage. Unpacking needs
  only the base and system stages, as
  in `fs_kernel`, which imports packages dnf downloaded.
* On vm-disk-dnf, Fedora's kernel package is dnf's: its modules are real
  directories in `/var/lib/pos/kernel/modules`, which `pos-kernel list`
  shows as `package` and leaves alone.

## Stage images
An optional stage (network, container, storage) ships with an installed system without being
part of its `/pos`: as a system extension image in the system's library
of stage images, which `pos-stage` enables. The stage arrives built, from
the same build as the rest, and nothing is downloaded or integrated on
the machine; enabling it runs only what a first boot runs for its files.

* `stage-images` makes the image of a stage with `sysext_stage`
  (`buildsys/output-plugins.d/sysext.sh`): `pos-<stage>-<stem>.raw`, an
  EROFS file system (lz4hc) of the stage's `/pos`, with
  `/usr/lib/extension-release.d/extension-release.pos-<stage>`. Its `ID`
  and `SYSEXT_LEVEL` are those of the base stages' os-release (system's),
  where assemble.sh writes the build's identifier as `SYSEXT_LEVEL`:
  systemd-sysext merges an image only onto the build it was made with.
* Stages depend on stages, not on packages. `sysext_stage` writes the
  stages an image needs besides the base, `pos-<stage>-<stem>.requires`:
  those whose member lists name a run-time requirement of the stage's
  packages (their installed meta). The container stage requires network
  (netavark requires nftables); nothing is declared twice.
* `fs_stage_images` (fs.sh) puts the images into an image's library,
  `/pos/lib/pos/stages/pos-<stage>.raw` with `pos-<stage>.requires`.
  vm-disk has one, so it is made once the optional stages are assembled
  too.
* `pos-stage` (`/pos/sbin`, pos-integration) enables a stage: it links the
  image into `/etc/extensions`, and the images of the stages it requires
  first, runs `systemd-sysext refresh`, which merges
  the enabled images over `/pos` read-only and reloads systemd, reloads
  udevd (it checks its rules at most every 3 seconds, and lvm2 waits without
  a timeout for a stage's rules to run), then
  `systemd-sysusers`, `systemd-tmpfiles --create` (the stage's factory
  files) and `ldconfig`. `pos-stage disable` removes the link and merges
  again, unless an enabled stage requires the stage; `pos-stage list`
  shows the library, with what each stage requires. systemd-sysext.service merges
  the enabled images at every boot, before tmpfiles runs; the stage's
  users were made when it was enabled and stay in `/etc/passwd`.
  Services a stage brings are not enabled: that is left to the
  administrator (`systemctl enable --now sshd`).
* systemd-sysext merges `/usr` and `/opt` unless `SYSTEMD_SYSEXT_HIERARCHIES`
  says otherwise. pos-integration's drop-in for systemd-sysext.service, and
  pos-stage, set it to `/pos`. The images' `/usr` (the extension-release)
  is not merged: `/usr` stays writable (`/usr/lib/modules`). The drop-in
  applies wherever POS's systemd runs, a pos-fedora system too, where it
  keeps Fedora's own extensions of `/usr` from merging; there the tools of
  the optional stages are Fedora's (see "RPM packages").
* An update replaces the library with the base, so an enabled stage stays
  the build's: the link in `/etc/extensions` names the library's path.
  smoke.sh enables the network stage and runs its tools where the library
  is, then the container stage, and runs containers.

## Images made with podman
`podman_build` makes an image with podman from the output's
`containerfile`, on top of the image of another output, which it requires.
It imports that output's archive into podman under its `tag`
(container-fs-dnf: `localhost/pos-dnf:<id>`) and builds on it, as `BASE`.
The result exists only in podman's local store, tagged with the build ID
and with the build's product version (`localhost/pos-fedora-toolbox:1.0`),
which moves to the build that made the image last. Builds made by other users
are in their own podman stores. `devtools/import-image.sh` imports the
other images of a build into podman the same way, or moves the version tag
back to an earlier build.

`fedora-toolbox` is container-fs-dnf as a toolbox image,
`localhost/pos-fedora-toolbox`, for working in a POS-based toolbox; builds
do not use it. It adds what toolbox needs and nothing installs:
toolbox puts its user in `wheel` with an empty password and runs sudo, so
the image adds a `wheel` rule in `/etc/sudoers.d` to POS's `/etc/sudoers`
(from the factory tree), which has none. sudo's PAM configuration is
POS's (see "System integration"). From Fedora's toolbox image it installs
with dnf: `flatpak-spawn` (toolbox run inside a toolbox, and `./build`,
reach the host with it), `p11-kit-client` (the host's trust store and smart
cards), `xorg-x11-xauth` (X11 programs on the host's display), nano as the
default editor and bash completion. Other tools are installed with dnf as
needed.

A toolbox stays on the image it was made from: moving to a later build is
making the toolbox again, from the image of that build.

    $ toolbox create -i localhost/pos-fedora-toolbox:<product version> <name>
    $ devtools/import-image.sh -o fedora-toolbox <id>   # back to build <id>

# RPM packages (experimental)
The outputs rpm-pos and rpm-pos-fedora make the RPM packages
of the build's assembled stages, when `run` assembles their stages or with
`./build output rpm-pos rpm-pos-fedora`. Each recipe says what
its packages are; `buildsys/output-plugins.d/rpm.sh` has what they share:
`rpm_stages` packages the merged trees of the output's stages (`pos`
and its debug info), `rpm_spec_head` and `rpm_build` make a
package of a spec, which rpm-pos-fedora writes itself. They are versioned with the build ID and written to
`work/builds/<id>/rpm`. dnf installs them as files, next to packages from
Fedora's repositories:

    $ sudo dnf --installroot=<root> --releasever=44 --use-host-config \
        install work/builds/<id>/rpm/pos{,-fedora}-1.0.0-1.main.202610171524.x86_64.rpm dnf

* `pos` is the `/pos` tree of the stages: the OS, as one
  package. It installs nothing outside `/pos` and provides nothing Fedora
  packages require, so it installs on any Fedora system without touching
  it, and is removed again with dnf.
* `pos-debuginfo` is its debug info in `/pos/lib/debug` (see "Debug
  info"); made when the build has any.
* `pos-fedora` makes a Fedora hybrid: it requires `pos` and stands in for the Fedora
  packages POS replaces. On a system built with it, dnf resolves Fedora
  packages against POS and installs only what POS does not have.

`devtools/try-rpm.sh` tries them out in a throwaway toolbox: `pos` next to
Fedora, or a root with POS as its base and Fedora packages on top, run
with podman:

    $ devtools/try-rpm.sh root vim-minimal curl
    $ devtools/try-rpm.sh run ldd /usr/bin/curl
    $ devtools/try-rpm.sh clean

`outputs/rpm-pos-fedora/fedora` lists the Fedora packages POS replaces,
by POS package; a line counts when its POS package is in the stages. For
those, pos-fedora:

* provides what they provide, as Fedora's repositories list it, at
  Fedora's versions: names, `name(x86-64)`, `config()`, `rtld(GNU_HASH)`,
  `user()` and `group()`. rpm creates their system users from the last
  ones when pos-fedora is installed. Their sonames and paths are not copied.
* provides the sonames and symbol versions of the POS libraries, made by
  rpm's own generator from the POS files, so a Fedora binary that needs a
  version POS does not have stays unresolved instead of failing to load.
* conflicts with them, so dnf picks pos-fedora for their names and an
  existing Fedora system is not changed by accident. pos-fedora is for
  building a system, not for converting one.
* links the POS programs into `/usr/bin` (Fedora's `/usr/sbin` and `/bin`
  are links to it) and the libraries and the loader into `/usr/lib64`, and
  provides the `/bin`, `/sbin`, `/usr/sbin` and `/lib64` names of them.
  Fedora binaries request `/lib64/ld-linux-x86-64.so.2`, so they run on
  POS glibc. A path that only Fedora packages pos-fedora does not replace
  have is not linked, so those install next to it.

The optional stages (network) have no RPM package, and pos-fedora claims
none of their packages: on an RPM system, Fedora's curl, openssh, iproute
and the others install in `/usr` as on Fedora. The stages are for native
systems, as images (see "Stage images").

A claim stands only if POS has every versioned soname and symbol version
the Fedora package provides; otherwise rpm-pos-fedora drops it with a warning
(listed in `rpm/pos-fedora.unmet`). Packages whose ABI differs from Fedora's
are left out of that list with the reason, and Fedora's copy is
installed next to POS where something needs it (OpenSSL 3 beside POS
OpenSSL 4).

Fedora packages installed next to POS put their libraries in `/usr/lib64`,
which the POS loader does not search by default. pos-fedora ships
`/etc/pos/ld.so.conf` (`/pos/lib`, then `/usr/lib64`) and runs
`/pos/sbin/ldconfig` after every package that adds libraries there or in
`/pos/lib`, so a later package's scriptlets find them. `/etc/ld.so.conf`,
which Fedora's glibc ships, links to it: tools that read the library path
there (dracut's) see the POS loader's.

dracut is POS's (in the system stage; GNU cpio is the base's): pos-fedora stands in
for Fedora's. Its configuration (`/pos/lib/dracut/dracut.conf.d/01-dist.conf`,
from `pos/system/packages/dracut`) names POS's directories of systemd, udev and dbus,
and the library directories, so an initramfs is made from POS's systemd.
The same dracut makes the initramfs when an image is made and on a running
system, through kernel-install.

rpmbuild's defaults are for Fedora's `/usr`, and every spec turns them off:
automatic dependencies (they would make `pos` provide `libc.so.6()(64bit)`
and replace Fedora without pos-fedora), and the post-install steps
(stripping, debug info, `/usr/lib/.build-id` links, man page compression,
shebang rewriting; the build strips and keeps debug info itself, see
"Debug info"). Modes come from the staging trees, with group write
removed as in images; set-uid bits are kept. `License` is `NOASSERTION`:
package metadata records no license yet. No source RPMs are made;
`--source-archives` covers the sources.

POS systemd reads units and drop-ins from `/pos/lib` and from `/usr/lib`,
where Fedora packages install them (see "Prefix"); generators only from
`/pos/lib/systemd`. Not covered yet: the POS compiler does not search
`/usr/include`, so Fedora `-devel` packages and the compiler are not
replaced.

# SDK
The sdk is the compiler, the assembler and linker (binutils, gcc): the
toolchain, built by toolchain builds of pos-sdk (see "Toolchain") and
installed in `/apps/pos-sdk/<version>` (see "Prefix"), apart from pos.
A pos build compiles with its toolchain reference's, and pos ships only
its gcc-runtime. The developer tools once in pos's sdk stage (diffutils,
patch) are pos-extras'.

binutils is what makes the sdk compiler self-contained. gcc execs `as` and
`ld`; without POS copies it would run the build container's, whose ld
searches `/usr/lib64` on its own. binutils is configured
`--with-lib-path=/pos/lib` so ld searches only `/pos/lib`, and gcc is given
the sdk's own (`--with-as=<sdk>/bin/as --with-ld=<sdk>/bin/ld`).

The compiler's own programs (cc1, cc1plus, lto1) are ordinary `/pos`
binaries, built without gcc's own staged bootstrap (`--disable-bootstrap`)
with the usual `/pos` link flags, running under the POS loader against
`/pos` glibc alone: gmp, mpfr, mpc, libstdc++ and libgcc are linked in
statically (see "Toolchain"). Built by Fedora's g++, that is Fedora's
`libstdc++.a` (`libstdc++-static`, which `gcc-host` installs). gcc's
top-level configure derives `CFLAGS_FOR_TARGET` from `CFLAGS`, which the
gcc recipes set to `-O2 -g -pipe` only (see "Build flags"), so the
hardening flags do not reach the target libraries; those are built by the
new xgcc with the patched defaults.

The run-time libraries are the gcc-runtime output of the gcc build:
libgcc_s, libstdc++, libatomic (the compiler links it by default and
libstdc++ depends on it) and libgomp. C and C++ programs need them at run
time, so gcc-runtime is in the core-libs stage and a base system has them
without the compiler. The split follows Fedora's libgcc, libstdc++,
libatomic and libgomp packages: gcc-runtime holds the `lib*.so.N` files
programs load, and the libstdc++ gdb pretty-printers. Everything used only
when compiling or linking stays in gcc: the C++ headers, the compiler's own
directory `lib/gcc/<target>/<version>` (crt files, `libgcc.a`, `unwind.h`,
`omp.h`), the static libraries (Fedora's `-static` packages), the
unversioned `lib*.so` names the linker looks up, `libgomp.spec` and
`libstdc++.modules.json`. The `.la` files are deleted, as Fedora does.
gcc links its LTO plugin into `<sdk>/lib/bfd-plugins`, as Fedora does,
so binutils' `ar`, `nm` and `ranlib` read LTO objects as `gcc-ar`,
`gcc-nm` and `gcc-ranlib` do.

The compiler searches `/pos/include` as its system header directory, so gcc
requires linux-headers, which core-libs ships with glibc's headers.

A pos-sdk release ships the gcc of a toolchain build made with the
previous toolchain (its toolchain reference). Two toolchain builds in a row from the same
sources should produce the same compiler; comparing them would be the
check gcc's own `make bootstrap` does. The pos package gmp is
`--enable-fat` because the archive is installed on other machines; gcc's
copy is built for gcc's own host triplet, generic x86-64.


# Base stage
The base stage (`pos/base/stage`) is what a POS system is without init
and kernel, as in a container: the shell, the core utilities, the login
and account tools, and transfer with curl. It is not a minimal set but a
generally functional userland. It builds on core-libs, and a pos
reference holds it with core-libs (see "Reference builds"), so pos-sdk
and pos-extras builds can take its tools and libraries.

* util-linux, procps and shadow link libsystemd (logind sessions,
  journal output; see "Circular dependencies"). libsystemd and libudev
  are systemd-libs, an output of the systemd build that the base stage
  lists, as Fedora's systemd-libs: the base has them without init. pam_systemd, in
  the base's PAM stack, is optional (`-session`) and works once systemd
  is there.
* POS's integration for the base is pos-integration-base, an output of
  pos-integration (see "System integration"): os-release, the PAM stack,
  `/etc/profile` and pos-preferences.
* file and which are user utilities. GNU which is the GNU
  project's git tree on Savannah, with its build system in the cwm4
  submodule; `pos/base/packages/which/prepare.sh` notes what its bootstrap needs.
* procps has the programs of Fedora's procps-ng: ps, top, free, pgrep,
  hugetop, pkill, pidof, pidwait, pmap, pwdx, skill, snice, slabtop, sysctl,
  tload, uptime, vmstat, w and watch, and libproc2. `w` reads sessions from
  logind. Its translated man pages are made by po4a (a host requirement),
  which leaves out those less than 80% translated.
* curl and libcurl: OpenSSL with OpenSSL's trust store (`/etc/ssl/cert.pem`,
  ca-certificates), HTTP/2 with nghttp2 (its library only), zlib and zstd.
  Not built for lack of the libraries: brotli, IDN (libidn2), libpsl,
  libssh2 (scp:, sftp:), GSSAPI, LDAP. pos-kernel downloads with it, and
  pos-extras' git links libcurl.

## Overlapping binaries
Several programs are shipped by more than one project. Fedora and LFS pick
differently; POS follows Fedora except where noted.

| program | providers | POS |
| --- | --- | --- |
| login, su, nologin, sulogin, runuser | util-linux, shadow | util-linux; shadow `--without-su`, login/nologin deleted |
| chfn, chsh | util-linux, shadow | util-linux; shadow's deleted |
| vipw, vigr, newgrp | util-linux, shadow | shadow (sg has no other provider); util-linux `--disable-vipw --disable-newgrp` |
| groups | coreutils, shadow | coreutils; shadow's deleted |
| kill | util-linux, coreutils, procps, bash builtin | util-linux; coreutils `--enable-no-install-program=kill`; procps `--disable-kill` |
| uptime | coreutils, procps | procps; coreutils leaves it out |
| pidof | procps, sysvinit | procps (Fedora) |
| hostname | coreutils (off by default), systemd hostnamectl | coreutils `--enable-install-program=hostname` |
| lastlog | shadow (deprecated), util-linux lastlog2 | util-linux lastlog2 with pam_lastlog2; shadow default off |
| sh | bash, dash | bash (Fedora, Arch). One shell in the base; dash is an option later |
| awk | gawk, mawk | gawk (Fedora, Arch), including `-M` via core-libs gmp and mpfr |
| pager | less, more (util-linux) | both; less is what man and systemd call |
| bus daemon | dbus-daemon, dbus-broker | reference dbus-daemon for now. Fedora and Arch run dbus-broker; revisit when the base boots |
| privilege | sudo, systemd run0, su | sudo shipped as planned; run0 comes with systemd anyway |
| scheduled jobs | cronie, systemd timers | both. cronie needs a `run-parts` for cron.hourly, which no listed package provides (Fedora: crontabs, Debian: debianutils) |
| log rotation | logrotate, journald | journald handles the journal; logrotate for other files |
| man | man-db + groff + gdbm, mandoc | neither in the base (Scope). If a viewer is ever added, mandoc is one package where man-db is four |
| rmt | tar, cpio (both from paxutils) | tar; cpio's deleted, it runs tar's at the same path |
| zic, zdump, tzselect | glibc, tzdata | glibc (Fedora); tzdata's deleted, it ships the data |
| passwd.5, getspnam.3, crypt.3 | man-pages, shadow, libxcrypt | man-pages (deferred, with man-db) for the first two, shadow's deleted; libxcrypt for crypt, man-pages' deleted |

# System stage
The system stage (`pos/system/stage`) is init and the service manager,
with what boots a system: kmod, dbus, cron and log rotation, the root's
file system tools and the initramfs. It builds on core-libs and base.

* Left out for now: man-db with its groff, gdbm and libpipeline
  dependencies (a page viewer that costs four packages; each package still
  installs its man pages under `/pos/share/man`). Their recipes remain in
  `pos/system/packages/` for reuse.
* e2fsprogs and dosfstools, the tools of the root's ext4 and the ESP's
  FAT: systemd-fsck checks them at boot with fsck.ext4 and fsck.vfat, and
  they resize and repair without a stage enabled. Other file systems are
  the storage stage's. e2fsprogs uses util-linux's libuuid, libblkid,
  fsck and uuidd; no fuse2fs.
* The QEMU guest agent (qemu-ga, pos/system/packages/qemu-guest-agent) answers the
  host's libvirt in a VM: guest IP addresses, `virsh guestinfo`, shutdown
  and reboot through the agent, file system freeze for quiesced snapshots,
  setting the clock and passwords. Its unit is qemu's, started by a udev
  rule of pos-integration when the VM has the agent's port
  (`org.qemu.guest_agent.0`, which virt-manager and vm.sh add), so it does
  nothing elsewhere. QEMU is synced as a subset of its tree, without the
  firmware submodules and prebuilt firmware, and only the agent is built:
  configure runs offline (`--disable-download`) with keycodemapdb, the one
  subproject it checks for, fetched by `pos/system/packages/qemu/prepare.sh`, and
  configure's Python packages from the build host. glib, its library, is
  built from git with gvdb as a submodule; its Python code generators
  (gdbus-codegen, glib-mkenums, glib-genmarshal, gtester-report) are not
  shipped, POS has no Python. SPICE's vdagent is left out: clipboard and display resizing
  need a graphical session.

## Deferred
* polkit: needs glib (built, for the guest agent) and duktape. duktape's
  git tree generates its sources with a Python 2 `dist.py`; only release
  tarballs are buildable. systemd only dlopens polkit at run time, so nothing else in the
  stage waits on it.
* gettext tools: the base ships gettext-runtime only (gettext, ngettext,
  envsubst; libintl is glibc's). msgfmt, xgettext and autopoint are build
  tools, not part of pos.

## Circular dependencies
systemd links libmount and libblkid from util-linux, and util-linux links
libsystemd (journal output for logger/lslogins) from systemd-libs, an
output of systemd. util-linux-bootstrap,
`--without-systemd`, is what systemd is built against; util-linux is built
after systemd `--with-systemd`. shadow and procps require systemd-libs,
and dbus systemd, so their logind and sd_notify integration is on.

systemd builds against cryptsetup (it dlopens libcryptsetup), which links
libdevmapper from lvm2, and lvm2 links libudev and libsystemd.
`lvm2-bootstrap` is lvm2's device-mapper part without udev
synchronization or libsystemd (`lvm2_make`, `lvm2_install` and
`configure_extra` set before sourcing lvm2's recipe); cryptsetup requires
it and `util-linux-bootstrap`, and lvm2 provides and obsoletes it, as
util-linux does `util-linux-bootstrap`. A stage image's requirements on
such a capability count for the stage of the package that provides it
(`sysext_stage_of`).

## System integration
`pos-integration` is POS's own package for the files that make the
packages one system and that no upstream ships. Its base stage part is
an output, pos-integration-base: os-release, the PAM stack, `/etc/profile`
and pos-preferences; the rest (presets, udev rules, pos-stage, pos-kernel)
needs systemd and is the system stage's. Its source is
`pos/system/src/pos-integration`, a POS-owned tree (no upstream, so `get-latest.sh`
skips it); like any source, it is built from the committed tree. So far it
holds POS's PAM configuration: `system-auth`, the stack services include
(local accounts with `pam_unix`, a logind session with `pam_systemd`), a
file for every PAM service in POS (util-linux's login, su, runuser, chfn
and chsh, shadow's passwd, chpasswd and newusers, sudo, cronie's crond;
systemd installs its own), and `other`, which denies the rest. It is
installed into pam's vendor directory `/pos/share/pam/pam.d`, so it
applies without being copied to `/etc`, and `/etc/pam.d` overrides it per
service. shadow's and cronie's own files are not installed (shadow's are
for programs util-linux provides, with modules POS does not have).

It also holds the system's identity, `/pos/lib/os-release` (`ID=pos`;
see "Prefix"), and POS's systemd presets, `80-pos.preset`: networkd,
networkd-wait-online and resolved are enabled, ahead of systemd's
`90-systemd.preset` and of any preset a system adds. A system with POS as
its base is POS: pos-fedora stands in for Fedora's `fedora-release`
packages (`outputs/rpm-pos-fedora/fedora`), with their provides (dnf's
`system-release(releasever)`), so Fedora's identity and presets are not
installed.

Still missing for a bootable system: upstream cronie and logrotate install
no systemd units and no default `logrotate.conf`; `run-parts` has no
provider. These belong in pos-integration too (units, sysusers.d). The
policy for units no preset names is systemd's default, enable; Fedora's
`99-default-disable.preset` is not there.

# Network stage
The network stage (`pos/network/stage`) is the network tools, optional
on a system: it is not in `/pos` until enabled (see "Stage images"). It
builds on core-libs, base and system, whose systemd-networkd and
systemd-resolved configure the network without it.

* iproute2 (ip, ss, bridge, tc, devlink and the rest) with libmnl, libelf
  for tc's eBPF loader (no libbpf) and libcap; no arpd (Berkeley DB). Its
  default tables are in `/pos/share/iproute2`, which `/etc/iproute2`
  overrides per file.
* iputils: ping, tracepath, arping and clockdiff, without set-uid or file
  capabilities. ping uses ICMP datagram sockets, which systemd's sysctl
  defaults (`net.ipv4.ping_group_range`) allow every group; arping and
  clockdiff need root.
* ethtool, with netlink (libmnl). nftables with libnftnl and libmnl,
  readline for `nft -i` and JSON (jansson) for `nft -j`, which netavark
  writes its rules with (see "Container stage"); no iptables
  compatibility. nftables.service loads `/etc/nftables/rules/main.nft`
  where there is one.
* OpenSSH (ssh, sshd, scp, sftp, ssh-agent, ssh-keygen): configuration in
  `/etc/ssh` (factory), PAM on (the shipped `sshd_config`, edited in
  prepare) with pam's vendor file `sshd`, the privilege separation user
  `sshd` (sysusers.d) and directory `/var/empty/sshd`. POS's units:
  sshd.service (`Type=notify`; sshd notifies systemd itself) and
  sshd-keygen.service, which makes the missing host keys before sshd
  starts. No Kerberos, libedit, FIDO security keys or SELinux.

Wi-Fi (iwd, iw, wireless-regdb) and the packet capture tools are not in
the stage yet. Wget2 and rsync are pos-extras' (curl is the base's). RPM systems have no package of the stage: their network
tools are Fedora's (see "RPM packages").

# Container stage
The container stage (`pos/container/stage`) is podman and what it runs
containers with, optional as the network stage, which it requires (see
"Stage images"). podman is Go, netavark and aardvark-dns are Rust, built
with Fedora's compilers (see "Packages").

* podman, with rootlessport and quadlet (its systemd generators, in
  `/pos/lib/systemd`), its units, man pages and completions. Build tags as
  Fedora's, set by the recipe: seccomp, systemd (journald, sd-notify),
  sqlite (POS's, its database), libsubid (shadow's), Go's OpenPGP for
  signatures (no GPGME); no btrfs or AppArmor. The `/usr/share/containers`
  of podman's libraries, where vendor configuration is read, is
  `/pos/share/containers` (`configfile.systemConfigPath` at link time);
  `/etc/containers` stays the machine's. No podman-remote or docker
  compatibility script.
* containers-common, the configuration Fedora's package of that name has,
  from the container-libs tree (synced as a subset): the defaults of
  containers.conf, storage.conf, registries.conf, policy.json,
  seccomp.json, with their man pages. POS's settings are `00-pos.conf`
  drop-ins next to them: podman's helpers in `/pos` (`helper_binaries_dir`,
  conmon, catatonit, crun), the journald log driver, netavark, the overlay
  driver (rootless too, without fuse-overlayfs), and docker.io for short
  names. `/etc/containers` has its empty drop-in directories.
* crun (with core-libs' json-c; its libocispec submodule generates C from the OCI
  schemas with Python): cgroup v2 through systemd, eBPF device rules,
  seccomp, capabilities; no CRIU, Wasm or libkrun. conmon (glib,
  libsystemd), catatonit.
* Networks: pasta (passt) for rootless containers, podman's default.
  netavark for rootful bridges, with nftables rules written through
  `nft -j` and its DHCP proxy for macvlan; aardvark-dns resolves container
  names on podman's networks. Both in `/pos/libexec/podman`.
* Rootless containers need subordinate ids: shadow ships empty
  `/etc/subuid` and `/etc/subgid` (factory), so `useradd` gives every new
  user a range, and newuidmap and newgidmap are set-uid. A user made
  before needs `usermod --add-subuids --add-subgids`.

Not in the stage: buildah and skopeo (podman build and podman image cover
most of their use), toolbox, podman-remote, slirp4netns, fuse-overlayfs
and iptables, which podman's current defaults do without.

# Storage stage
The storage stage (`pos/storage/stage`) is file system, volume,
encryption and network storage tools, optional on a system: it is not in
`/pos` until enabled (see "Stage images"). It builds on core-libs, base
and system; the root's and the ESP's tools (e2fsprogs, dosfstools) are the
system stage's.

* File systems: xfsprogs, with liburcu (userspace-rcu) and inih, and ICU
  for xfs_scrub; xfs_scrub_all and xfs_protofile are Python scripts and
  are left out, with the xfs_scrub_all units. btrfs-progs, with
  btrfs-convert from ext2/3/4 (e2fsprogs' libraries), OpenSSL checksums,
  zstd and zlib; no LZO, as lzo is released only as tarballs, not git:
  restore, receive and mkfs --rootdir cannot handle LZO-compressed
  extents. exfatprogs.
* lvm2: the lvm tools, dmsetup, dmeventd, lvmpolld, libdevmapper, with
  udev synchronization, its udev rules and units, the devices file on by
  default; thin, cache, writecache and integrity volumes, checked with
  thin-provisioning-tools (Rust, built with Fedora's compiler as the
  container stage's). No VDO (vdoformat), no D-Bus service, and no NVMe
  WWIDs: lvm2 reads them with libnvme 1, and nvme-cli's tree now has
  libnvme 3, a new API. libaio for the tools' I/O. mdadm with mdmon, its
  udev rules (incremental assembly), units and shutdown hook.
* cryptsetup with veritysetup and integritysetup: OpenSSL, its Argon2
  too, kernel keyring tokens; no SSH token or pwquality. systemd dlopens
  libcryptsetup (see "Circular dependencies"): crypttab,
  systemd-cryptsetup, cryptenroll and homed's LUKS volumes work once the
  stage is enabled.
* open-iscsi (iscsid, iscsiadm, iscsistart, iscsiuio, the iBFT generator)
  with iSNS from open-isns. The initiator name is made on the machine by
  iscsi-init.service; the build's is not shipped, or machines would share
  it. nvme-cli with libnvme, NVMe over Fabrics discovery and autoconnect;
  no TLS keys (keyutils), mDNS or KMIP.
* smartmontools: smartctl, smartd and the drive database, which updates
  with POS (no update-smart-drivedb).

What the sources lack against a release, prepare makes as upstream's
release does: nvme-cli's committed man pages, which upstream regenerates
only for a release (newer commands have none on master), by its
update-docs target; smartmontools' `util/dist-version.sh` (make dist), by
its `getversion.sh` against the upstream history at the synced commit,
fetched without file contents. thin-provisioning-tools' devicemapper-sys
makes its bindings with bindgen, which needs libclang and the clang
driver's header paths: Fedora's clang, a build tool only.

Not in the stage: f2fs-tools, ntfs-3g, multipath-tools, targetcli (iSCSI
targets), Stratis, VDO.
