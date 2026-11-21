#!/bin/sh
# Download and unpack Tcl/Tk sources for one release line.
#
#   usage: sh fetch.sh <root> <version>
#     e.g. sh fetch.sh 8.6 8.6.18     -> 8.6/tcl, 8.6/tk
#          sh fetch.sh 9.0 9.0.4      -> 9.0/tcl, 9.0/tk
#
# Tarballs are cached in dl/. An already unpacked tree of the same version
# is left alone; a tree of a different version is replaced.
#
# After unpacking, the patches in patches/tcl<root>/ and patches/tk<root>/
# are applied (patch -p1), if there are any.

set -e

URL=${TCL_URL:-https://prdownloads.sourceforge.net/tcl}
top=`cd \`dirname $0\` && pwd`

if test $# != 2; then
  echo "usage: sh fetch.sh <root> <version>" >&2; exit 1
fi
root=$1
ver=$2

mkdir -p "$top/dl" "$top/$root"

for p in tcl tk; do
  # Tk 8.x patchlevels occasionally lag behind Tcl; allow TK_VERSION override.
  v=$ver
  case $p in tk) v=${TK_VERSION:-$ver} ;; esac
  tar=$p$v-src.tar.gz
  dir=$top/$root/$p

  if test -f "$dir/.version" && test "`cat $dir/.version`" = "$v"; then
    echo "$root/$p is already $v"
    continue
  fi

  if test ! -s "$top/dl/$tar"; then
    echo "fetching $tar"
    if command -v curl >/dev/null 2>&1; then
      curl -fL --retry 3 -o "$top/dl/$tar.part" "$URL/$tar"
    else
      wget -O "$top/dl/$tar.part" "$URL/$tar"
    fi
    mv "$top/dl/$tar.part" "$top/dl/$tar"
  fi

  echo "unpacking $tar -> $root/$p"
  rm -rf "$dir" "$top/$root/$p$v"
  tar -C "$top/$root" -xzf "$top/dl/$tar"
  mv "$top/$root/$p$v" "$dir"

  # local fixes, e.g. what old releases need to compile with current tools
  for pf in "$top/patches/$p$root"/*.patch; do
    test -f "$pf" || continue
    echo "applying patches/$p$root/`basename $pf`"
    patch -p1 -s -d "$dir" < "$pf"
  done

  echo "$v" > "$dir/.version"
done
