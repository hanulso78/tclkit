#!/bin/sh
# Build and package tclkits for one or more Tcl/Tk releases.
#
#   usage: sh mkdist.sh ?-c? ?-j n? ?version ...?
#
#     -c      remove the build directories first (clean rebuild)
#     -j n    number of parallel make jobs (default: number of processors)
#
#   Without versions, the releases listed in VERSIONS below are built.
#
# For every version this
#   1. downloads and unpacks the Tcl/Tk sources          (fetch.sh)
#   2. configures <root>/kit-large and <root>/kit-small  (config.sh)
#   3. builds both
#   4. packs the executables into
#        dist/tclkit-large-<version>-<platform>.7z
#        dist/tclkit-small-<version>-<platform>.7z
#
#   large = cli + gui, threaded, all encodings, message catalogs and timezones
#   small = cli + dyn (Tk as a shared library inside the kit), basic encodings
#
# The 8.x kits also contain the classic Metakit based tclkit/tclkitsh pair.
# Tcl 9 kits are zipfs based, see README.

VERSIONS="8.4.20 8.5.19 8.6.18 9.0.4"

set -e

top=`cd \`dirname $0\` && pwd`
cd "$top"

clean=0
jobs=${NUMBER_OF_PROCESSORS:-`getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2`}

while test $# != 0; do
  case $1 in
    -c) clean=1 ;;
    -j) shift; jobs=$1 ;;
    -*) echo "usage: sh mkdist.sh ?-c? ?-j n? ?version ...?" >&2; exit 1 ;;
    *)  break ;;
  esac
  shift
done

test $# != 0 && VERSIONS="$*"

# platform tag used in the archive names, e.g. win-amd64 or linux-x86_64
machine=`${CC:-gcc} -dumpmachine 2>/dev/null || uname -m`
case $machine in
  x86_64*|amd64*) arch=amd64 ;;
  i?86*)          arch=x86 ;;
  aarch64*|arm64*) arch=arm64 ;;
  *)              arch=`echo $machine | cut -d- -f1` ;;
esac
case `uname` in
  MINGW*|MSYS*) plat=win-$arch; exe=.exe ;;
  Darwin)       plat=macosx-$arch; exe= ;;
  *)            plat=`uname | tr A-Z a-z`-$arch; exe= ;;
esac

pack() {
  # pack <archive-basename> <dir> <file ...>
  out=$top/dist/$1; dir=$2; shift; shift
  rm -f "$out.7z" "$out.tar.gz"
  if command -v 7z >/dev/null 2>&1; then
    (cd "$dir" && 7z a -t7z -mx=9 -bd "$out.7z" "$@" >/dev/null)
    echo "  -> dist/`basename $out`.7z"
  else
    (cd "$dir" && tar -czf "$out.tar.gz" "$@")
    echo "  -> dist/`basename $out`.tar.gz"
  fi
}

build() {
  # build <root> <version> <kind> <config options ...>
  root=$1; ver=$2; kind=$3; shift; shift; shift
  dir=$root/kit-$kind

  echo "== tclkit-$kind $ver ($plat)"
  test $clean = 1 && rm -rf "$dir/build"
  sh config.sh $dir "$@" >/dev/null
  if ! (cd $dir && make -j$jobs >build.log 2>&1); then
    echo "   BUILD FAILED, see $dir/build.log" >&2
    tail -20 $dir/build.log >&2
    return 1
  fi

  files=
  for f in tclkit-cli tclkit-dyn tclkit-gui tclkitsh tclkit; do
    test -f $dir/$f$exe && files="$files $f$exe"
  done
  pack tclkit-$kind-$ver-$plat $dir $files
}

mkdir -p dist
failed=

for ver in $VERSIONS; do
  root=`echo $ver | cut -d. -f1-2`
  sh fetch.sh $root $ver

  case $root in
    8.*) large="cli gui mk thread allenc allmsgs tzdata"
         small="cli dyn mk" ;;
    *)   large="cli gui thread itcl sqlite allenc allmsgs tzdata"
         small="cli dyn" ;;
  esac

  build $root $ver large $large || failed="$failed large-$ver"
  build $root $ver small $small || failed="$failed small-$ver"
done

echo
ls -l dist
if test -n "$failed"; then
  echo "FAILED:$failed" >&2
  exit 1
fi
