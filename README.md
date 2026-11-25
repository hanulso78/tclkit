# tclkit

Build scripts for **Tclkit**, the single file Tcl/Tk runtime, for Tcl/Tk 8.4,
8.5, 8.6 and 9.0. Based on [kitgen](http://github.com/patthoyts/kitgen/) by
Jean-Claude Wippler and Pat Thoyts, brought up to date for current
MinGW-w64 compilers and extended with a zipfs based kit for Tcl 9.

A tclkit is one executable that contains the Tcl interpreter together with its
script library. Wrap your own scripts and packages into it and you get an
application that runs by just copying a single file.

## Download

Pre-built packages for 64-bit Windows:

<https://tcl.oscc.kr/?dir=tclkit>

| Package | Executables | Contents |
|---|---|---|
| `tclkit-large-8.x` | `tclkit-cli`, `tclkit-gui`, `tclkitsh`, `tclkit` | threaded, Thread extension, all encodings, message catalogs and time zones (8.5+) |
| `tclkit-small-8.x` | `tclkit-cli`, `tclkit-dyn`, `tclkitsh` | basic set of encodings |
| `tclkit-large-9.x` | `tclkit-cli`, `tclkit-gui` | Thread, itcl 4 and sqlite3 linked in, all encodings, message catalogs and time zones |
| `tclkit-small-9.x` | `tclkit-cli`, `tclkit-dyn` | basic set of encodings |

| Executable | |
|---|---|
| `tclkit-cli` | console version, no Tk |
| `tclkit-gui` | Tk linked in statically, no console window |
| `tclkit-dyn` | console version carrying Tk as a shared library, loaded on `package require Tk` |
| `tclkitsh`, `tclkit` | 8.x only: the classic Metakit based pair (console / Tk), with Itcl 3.4 |

On 8.x, `tclkit-*` are "Tclkit Lite", which reads kits with vlerq, while
`tclkitsh` / `tclkit` contain the full Metakit. `sdx` runs with either kind.
On Linux the small 8.x archive also has `tclkit`, which loads Tk from the
shared library inside the kit.

## Using a tclkit

| | |
|---|---|
| [HOWTOUSE.HTML](HOWTOUSE.HTML) | making a single file application with Tcl 8.4 / 8.5 / 8.6 and sdx |
| [HOWTOUSE9.HTML](HOWTOUSE9.HTML) | the same with Tcl 9 |

The application directory is the same for all versions:

    demo.vfs/
        main.tcl            startup script
        lib/                packages of the application
        ...

    # main.tcl
    package require starkit
    starkit::startup
    source [file join $starkit::topdir app demo.tcl]

Wrapping differs. With **8.x**, use [sdx](https://wiki.tcl-lang.org/page/sdx):

    tclkitsh sdx.kit wrap demo -runtime runtime.exe

With **9.x**, wrapping is built into the tclkit and sdx is not used:

    tclkit -wrap demo.exe demo.vfs
    tclkit -wrap demo.exe demo.vfs -runtime tclkit-gui.exe
    tclkit -wrap demo.exe demo.vfs -icon demo.ico     # Windows: other icons
    tclkit -wrap demo.kit demo.vfs        # just the application, run as: tclkit demo.kit

### Tcl 9 is different inside

Tcl 9 has zipfs in the core, so the Tcl 9 tclkit appends an ordinary zip
archive to the executable and contains no Metakit, vlerq or tclvfs.

* A Metakit based `.kit` file made for 8.x, `sdx.kit` included, does not run
  on it. Wrap the application again from its source directory.
* A `.kit` for Tcl 9 is a plain zip file with `main.tcl` at the top level.
* `package require starkit`, `starkit::startup` and `$starkit::topdir` work as
  before. `vfs::*`, `Mk4tcl` and `vlerq` are not available; use `zipfs`.
* Files inside the executable are read-only.

## Building

Tested on Windows with [MSYS2](https://www.msys2.org/), MINGW64 shell,
gcc 16.1. The details are in [HOWTOBUILD.HTML](HOWTOBUILD.HTML).

    pacman -S --needed mingw-w64-x86_64-gcc make patch p7zip zip curl
    sh mkdist.sh

`mkdist.sh` downloads the Tcl/Tk sources, builds a large and a small set of
kits for each release and packs them into `dist/`:

    dist/tclkit-large-<version>-win-amd64.7z
    dist/tclkit-small-<version>-win-amd64.7z

On Linux the same command gives `tclkit-{large,small}-<version>-linux-x86_64`,
as `.tar.gz` when there is no `7z`.

    sh mkdist.sh 8.6.18 9.0.4     # only these releases
    sh mkdist.sh -c               # clean rebuild
    sh mkdist.sh -j 4             # number of parallel make jobs

The releases built by default are listed in `VERSIONS` at the top of the
script: 8.4.20, 8.5.19, 8.6.18 and 9.0.4.

### One configuration by hand

    sh fetch.sh 8.6 8.6.18
    sh config.sh 8.6/kit-large cli gui mk thread allenc allmsgs tzdata
    cd 8.6/kit-large
    make

* `fetch.sh <root> <version>` downloads the sources to `dl/`, unpacks them to
  `<root>/tcl` and `<root>/tk` and applies the patches in `patches/`.
* `config.sh <root>/<name> <options>` writes `<root>/<name>/Makefile`. `<root>`
  selects the sources and has to exist; `<name>` is up to you, `kit-something`
  by convention.
* `make` builds in `build/` below that directory and leaves the executables
  next to the Makefile. `make clean` removes `build/`, `make distclean` the
  executables as well.

### Options of config.sh

| Option | |
|---|---|
| `cli` | build `tclkit-cli` |
| `dyn` | build `tclkit-dyn` |
| `gui` | build `tclkit-gui` |
| `mk` | 8.x: also build the Metakit based `tclkitsh` / `tclkit` |
| `thread` | 8.x: threaded Tcl with the Thread extension as a shared library inside the kit; 9.x: Thread linked in statically |
| `itcl`, `sqlite` | 9.x: link in itcl 4 / sqlite3 from the `pkgs/` directory of Tcl |
| `allenc` | all encodings instead of the basic set |
| `allmsgs` | the localized message catalogs of Tcl (8.5 and later) |
| `tzdata` | the time zone data files (8.5 and later) |
| `b64` | 64-bit build where that is not the default of the compiler |
| `sym` | keep debugging symbols |
| `gprof`, `gcov` | profiling / code coverage, 8.x (imply `sym`) |
| `aqua`, `univ`, `ppc`, `x86` | Mac OS X, 8.x |
| `ext=dir` | link the static packages in `dir` into `tclkit-gui`, see below |

Without `cli`, `dyn` or `gui`, all three are built.

### Static packages in tclkit-gui

`ext=dir` links compiled extensions into `tclkit-gui`, so that it carries
them with no shared libraries beside it. `dir` holds:

| | |
|---|---|
| `*.a` | the static libraries of the packages |
| `init.c` | `void TclKit_ExtInit(void)`, which registers them with `Tcl_StaticPackage` (8.x) or `Tcl_StaticLibrary` (9.x) |
| `ldflags` | one line: the libraries they need, linked after them |
| `vfs/` | optional: copied into the kit, e.g. `vfs/lib/<pkg>/pkgIndex.tcl` with `load {} Name` and the package's scripts |

The packages are compiled against the stub libraries (`-DUSE_TCL_STUBS
-DUSE_TK_STUBS`) like for a shared library; the link adds the kit's own
Tk stub library. Only `tclkit-gui` takes them, `cli` and `dyn` stay as they are.

    sh config.sh 8.6/kit-mine gui thread allenc allmsgs tzdata ext=/path/to/dir
    cd 8.6/kit-mine && make

What `mkdist.sh` uses:

    large, 8.x:  cli gui mk thread allenc allmsgs tzdata
    small, 8.x:  cli dyn mk
    large, 9.x:  cli gui thread itcl sqlite allenc allmsgs tzdata
    small, 9.x:  cli dyn

### Linux

`sh mkdist.sh` works unchanged. It needs gcc, g++, make, patch, curl and the
development files of X11, Xft and fontconfig. All four releases have been built
on AlmaLinux 8 (gcc 8.5, glibc 2.28), so those kits run on that glibc or newer.
The console kits depend on libc only (libstdc++ too for the Metakit ones, zlib
for Tcl 9); the ones with Tk linked in also need the X11, Xft and fontconfig
libraries at run time. Tk 8.4 is built without Xft.

### Other platforms

The BSD, Solaris and Mac OS X settings of the original kitgen are still in
`config.sh`, but none of that has been built with these changes. `Makefile.vc` is the old MSVC build of kitgen
for 8.x; it is unchanged and knows nothing about Tcl 9.

## Layout

    8.4/ 8.5/ 8.6/ 9.0/     one directory per release line
        tcl/ tk/            sources, put there by fetch.sh
        kit-large/          build configurations, made by config.sh
        kit-small/
    8.x/                    extensions for the 8.x kits:
                            itcl, mk (Metakit), tclvfs, thread, vqtcl, zlib
    patches/                fixes for old releases, applied by fetch.sh
    files/                  files which go into the kits
    dl/                     downloaded source tarballs
    dist/                   packed results

    mkdist.sh               build and pack everything
    fetch.sh                get the sources of one release
    config.sh               set up one build configuration

    makefile.include        8.x: the build rules
    kitInit.c               8.x: application init
    setupvfs.tcl            8.x: fills the Metakit/vlerq file system of a kit
    validate.tcl            8.x: checks a new kit

    makefile9.include       9.x: the build rules
    kitInit9.c              9.x: application init, kit files, -wrap
    setupvfs9.tcl           9.x: fills and attaches the zip archive
    validate9.tcl           9.x: checks a new kit

    docs.css, mkdocs.tcl    style sheet of the HTML documents; mkdocs.tcl
                            puts it into them

### How a kit comes about

**8.x.** Tcl, Tk and the extensions are built as static libraries and linked
with `kitInit.c` into a "raw" kit, `kit-cli`. That executable cannot start
normally yet, as it has no script library. It is run once with `-init-` to
execute `setupvfs.tcl`, which copies the runtime files into a Metakit
datafile appended to the final executable. So a tclkit is built from scratch,
without needing an existing tclkit.

**9.x.** Tcl and Tk are built as static libraries and linked with the
unmodified `tclAppInit.c` / `winMain.c` plus `kitInit9.c`. The new `kit-cli`
then runs `setupvfs9.tcl` with the library of the source tree, which collects
the files and attaches them with `zipfs mkimg`:

    tcl_library/    Tcl script library
    tk_library/     Tk script library (gui, dyn)
    lib/            package indexes of the static extensions, the Tk
                    library (dyn), starkit, tclkit::wrap
    main.tcl        added by "tclkit -wrap": the application

### Patches

Applied by `fetch.sh` after unpacking; they are what the old releases need to
compile and work with a current MinGW-w64.

| Patch | |
|---|---|
| `tcl8.4`, `tk8.4`: `mingw-w64-seh` | `EXCEPTION_REGISTRATION` clashes with a type in the current Windows headers; renamed as Tcl 8.5 did |
| `tcl8.4`: `win64-threadid` | the id of a new thread had random upper 32 bits on Win64, so `thread::send` could not find the thread; fix taken from Tcl 8.5 |
| `tk8.4`, `tk8.5`: `controlmask` | `ControlMask` clashes with a struct member in the current Windows headers; made an enum as Tk 8.6 did |

## License

The Tclkit-specific sources are license free, they just have a copyright. Hold
the author(s) harmless and any lawful use is permitted.

This does *not* apply to the sources of the other Open Source software used in
Tclkit, each of which has a liberal BSD/MIT-like license of its own:
Tcl/Tk, TclVFS, Thread, Vlerq, Metakit, Itcl, Zlib, SQLite.

`HOWTOUSE.HTML` is a copy of an article by Ashok P. Nadkarni, see the
copyright notice in it.

## Acknowledgements

With thanks to John Ousterhout for creating Tcl/Tk, Matt Newman and Vince
Darley for developing the virtual file system, and the members of the Tcl Core
Team for diligently maintaining and taking forward the Tcl/Tk code base plus
extensions.

Tclkit and kitgen are the work of Jean-Claude Wippler, with Pat Thoyts,
Brian Theado and many others who contributed suggestions, bug reports and
fixes over the years. Thanks also to Eolas Technologies Inc for sponsoring
the Vlerq project on which Tclkit Lite is based.
