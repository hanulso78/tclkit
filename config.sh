#set -x

args="$*"

verbose=0; case $1 in -v) verbose=1; shift ;; esac

root=`dirname $1`
base=`basename $1`
shift

case $root in .) root=8.4;; esac
path=$root/$base
  
if test ! -d $root
  then echo "error: directory '$root' does not exist"; exit 1; fi

for v in allenc allmsgs aqua b64 cli dyn gui ppc mk \
          gcov gprof sym thread tzdata univ x86 itcl sqlite
  do eval $v=0; done
ext=

# ext=dir: static packages to link into tclkit-gui (see README.md)
while test $# != 0
  do case $1 in
       ext=*)
         ext=`cd "${1#ext=}" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }` ||
           { echo "error: directory '${1#ext=}' does not exist"; exit 1; }
         for f in init.c ldflags; do
           test -f "$ext/$f" || { echo "error: $ext has no $f"; exit 1; }
         done ;;
       *) eval $1=1 ;;
     esac
     shift
  done

#for v in thread allenc allmsgs tzdata cli dyn gui aqua x86 ppc univ
#  do eval val=$`echo $v`; echo $v = "$val"; done

make=$path/Makefile
mach=`uname`
plat=unix
upx=`which upx`

echo "Configuring $make for $mach."
mkdir -p $path

case $cli-$dyn-$gui in 0-0-0) cli=1 dyn=1 gui=1 ;; esac

# Tcl 9 and later: zipfs based kits, see makefile9.include. No Metakit, vlerq
# or tclvfs; "thread", "itcl" and "sqlite" select the extensions bundled with
# the Tcl sources (pkgs/) which get linked in statically.
case `basename $root` in 8*) ;; *)
  ( echo "# Generated `date`:"
    echo "#   `basename $0` $args"
    echo
    echo "CC         = ${CC:=gcc}"
    case $mach in
      MINGW*)
        echo 'CFLAGS    += -O2 -static'
        echo 'PLAT       = win'
        echo 'EXE        = .exe'
        echo 'SO         = .dll'
        echo 'UNICODE_DEFS = -DUNICODE -D_UNICODE'
        echo 'TCLLIBS    = $(wildcard build/tcl/libtcl[0-9][0-9].a) build/tcl/libtclstub.a'
        echo 'TKLIBS     = $(wildcard build/tk/libtcl9tk[0-9][0-9].a build/tk/libtk[0-9][0-9].a)'
        echo 'CLIRES     = build/tcl/tclsh.res.o'
        echo 'GUIRES     = build/tk/wish.res.o'
        echo 'CLI_OPTS   = -mconsole -municode'
        echo 'GUI_OPTS   = -mwindows -municode'
        echo 'TKMAIN     = winMain.c'
        ;;
      Darwin)
        echo 'CFLAGS    += -O2'
        echo 'PLAT       = unix'
        echo 'LDSTRIP    = -x'
        echo 'SO         = .dylib'
        echo 'TCLLIBS    = $(wildcard build/tcl/libtcl9*.a) build/tcl/libtclstub.a'
        echo 'TKLIBS     = $(wildcard build/tk/libtcl9tk*.a build/tk/libtk9*.a)'
        echo 'TKMAIN     = tkAppInit.c'
        case $aqua in 1)
          echo "TK_OPTS    = --enable-aqua"
          echo "TKDYN_OPTS = --enable-aqua" ;;
        esac
        ;;
      *)
        echo 'CFLAGS    += -O2'
        echo 'PLAT       = unix'
        echo 'TCLLIBS    = $(wildcard build/tcl/libtcl9*.a) build/tcl/libtclstub.a'
        echo 'TKLIBS     = $(wildcard build/tk/libtcl9tk*.a build/tk/libtk9*.a)'
        echo 'TKMAIN     = tkAppInit.c'
        ;;
    esac

    pkgs=
    case $thread in 1) pkgs="$pkgs thread" ;; esac
    case $itcl   in 1) pkgs="$pkgs itcl" ;; esac
    case $sqlite in 1) pkgs="$pkgs sqlite" ;; esac
    echo "PKGS       =$pkgs"

    case $allenc  in 1) kitopts="$kitopts -e" ;; esac
    case $allmsgs in 1) kitopts="$kitopts -m" ;; esac
    case $tzdata  in 1) kitopts="$kitopts -z" ;; esac
    echo "KIT_OPTS   =$kitopts"

    case $sym in 1)
      echo "STRIP      = :"
      echo "TCL_OPTS  += --enable-symbols"
      echo "TK_OPTS   += --enable-symbols"
      echo "TKDYN_OPTS += --enable-symbols"
      echo "PKG_OPTS  += --enable-symbols" ;;
    esac

    targets=
    case $cli in 1) targets="$targets tclkit-cli\$(EXE)" ;; esac
    case $dyn in 1) targets="$targets tclkit-dyn\$(EXE)" ;; esac
    case $gui in 1) targets="$targets tclkit-gui\$(EXE)" ;; esac
    echo
    echo "all:$targets"
    echo
    case $ext in ?*) echo "KITEXT     = $ext"; echo ;; esac
    echo "include ../../makefile9.include"
  ) >$make
  case $verbose in 1) cat $make ;; esac
  exit 0 ;;
esac

( echo "# Generated `date`:"
  echo "#   `basename $0` $args"
  echo
  
  case $mach in
  
    Darwin)
      case $aqua in
        1) echo "GUI_OPTS   = -framework Carbon -framework IOKit" ;;
        *) echo "GUI_OPTS   = -L/usr/X11R6/lib -lX11 -weak-lXss -lXext" ;;
      esac
      
      echo "LDFLAGS    = -framework CoreFoundation"
      echo "LDSTRIP    = -x"
      echo "SO         = .dylib"
      
      case $b64-$univ-$ppc-$x86 in
        0-0-0-0) ;;
        0-0-1-0) echo "CFLAGS    += -arch ppc" ;;
        0-0-0-1) echo "CFLAGS    += -arch x86" ;;
        0-?-?-?) echo "CFLAGS    += -arch ppc -arch i386" ;;
        1-0-1-0) echo "CFLAGS    += -arch ppc64" ;;
        1-0-0-1) echo "CFLAGS    += -arch x86_64" ;;
        1-?-?-?) echo "CFLAGS    += -arch ppc64 -arch x86_64" ;;
      esac
      echo "CFLAGS    += -isysroot /Developer/SDKs/MacOSX10.4u.sdk" \
                          "-mmacosx-version-min=10.4"
      
      case $aqua in 1)
        echo "TK_OPTS    = --enable-aqua"
        echo "TKDYN_OPTS = --enable-aqua" ;;
      esac
      ;;
      
    Linux)
      echo "CC         = ${CC:=gcc}"
      echo "CXX        = ${CXX:=gcc}"
      # Tcl 8.6 is threaded even when not asked for
      echo "LDFLAGS    = -ldl -lm -lpthread"
      # keep our own zlib private: shared libraries of the system (libpng
      # by way of Xft) must go on using the zlib they were linked with
      echo "LDFLAGS   += -Wl,--exclude-libs,libz.a"
      # static extensions are built to use the stubs table
      echo "LDFLAGS   += build/lib/libtclstub8*.a"
      # the C++ runtime (Metakit) statically if that library is installed
      if echo 'int main(){return 0;}' | \
           ${CXX:-g++} -x c++ - -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic \
             -o /dev/null 2>/dev/null; then
          echo "LDXXFLAGS  = -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic"
      else
          echo "LDXXFLAGS  = -lstdc++"
      fi
      echo "GUI_OPTS   = -L/usr/X11R6/lib -lX11"
      # Tk uses the screen saver extension only if its headers are there
      if echo 'int main(void){return 0;}' | \
           $CC -x c - -lXss -o /dev/null 2>/dev/null; then
          echo "GUI_OPTS  += -lXss"
      fi
      if [ $root != "8.4" ]; then
          echo "GUI_OPTS  += -lXft -lfontconfig -lXext"
      fi
      case $b64 in 1)
        echo "CFLAGS     += -m64" ;;
      esac
      [ -n "$upx" ] && [ -x "$upx" ] && echo "UPX        = $upx"
      ;;

    *BSD)
      echo "CC         = ${CC:=gcc}"
      echo "CFLAGS    += -I/usr/X11R6/include"
      echo "LDFLAGS    = -lm"
      echo "GUI_OPTS   = -L/usr/X11R6/lib -lX11 -lXss"
      case $b64 in 1)
        echo "CFLAGS     += -m64" ;; 
      esac
      ;;

    MINGW*)
      echo "CC         = ${CC:=gcc}"
      echo 'CFLAGS    += -I'`pwd`'/'$root'/tcl/win -I'`pwd`'/'$root'/tk/win'
      echo 'CFLAGS    += -static-libgcc -static-libstdc++ -static'
      # gcc 14+ turns implicit declarations, int/pointer mismatches etc. into
      # hard errors and gcc 15+ defaults to C23. The Tcl 8.x era sources (and
      # their autoconf tests) need the older, more permissive dialect.
      gccmajor=`$CC -dumpversion 2>/dev/null | cut -d. -f1`
      if [ "${gccmajor:-0}" -ge 14 ]; then
          echo 'CFLAGS    += -std=gnu17 -fpermissive -w'
      fi
      echo 'LDFLAGS    = build/lib/dde1*/*tcldde1*.a build/lib/reg1*/*tclreg1*.a'
      [ $root != "8.4" ]   && echo 'LDFLAGS   += -lws2_32'
      if [ ${root#8.} -ge 6 ]; then
          echo 'LDFLAGS   += -lnetapi32 -luserenv'
          echo 'LDFLAGS   += build/lib/*tclstub8*.a'
      fi
      echo 'GUI_OPTS   = -lgdi32 -lcomdlg32 -limm32 -lcomctl32 -lshell32'
      echo 'GUI_OPTS  += -lole32 -loleaut32 -luuid'
	  echo 'GUI_OPTS  += -mwindows'
      #echo 'GUI_OPTS  += build/tk/wish.res.o -mwindows'
      echo 'CLIOBJ     = $(OBJ) $(OUTDIR)/tclAppInit.o $(OUTDIR)/tclkitsh.res.o'
      echo 'DYNOBJ     = $(CLIOBJ) $(OUTDIR)/tkdyn/wish.res.o'
      echo 'GUIOBJ     = $(OBJ) $(OUTDIR)/winMain.o $(OUTDIR)/tclkit.res.o'
      echo 'PRIV       = install-private-headers'
      # Tk is built against a static Tcl and so sees STATIC_BUILD, which
      # leaves its API without dllexport: export everything explicitly.
      echo 'TKDYN_CFLAGS = -Wl,--export-all-symbols'
      echo 'SO         = .dll'
      echo 'EXE        = .exe'
      [ -x $upx ] && echo "UPX        = $upx"
      plat=win
      ;;

    SunOS)
      echo "CC         = ${CC:=gcc}"
      echo "CXX        = ${CXX:=gcc}"
      echo "CFLAGS    += -I/usr/openwin/include"
      echo "LDFLAGS    = -ldl -lsocket -lnsl -lm"
      echo "LDXXFLAGS  = -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic"
      echo "GUI_OPTS   = -L/usr/openwin/lib -lX11 -lXext"
      if [ $root != "8.4" ]; then
          echo "GUI_OPTS  += -L/usr/sfw/lib -lXft -lfreetype -lz -lfontconfig -lXrender"
      fi
      case $b64 in 1)
        echo "CFLAGS += -m64" ;;
      esac
      ;;

    *) echo "warning: no settings known for '$mach'" >&2 ;;
  esac

  echo "PLAT       = $plat"
  echo "KITFLAGS   ="
  case $plat in unix)
    echo "PRIV       = install-private-headers" ;;
  esac
  case $b64 in 1)
    echo "TCL_OPTS   += --enable-64bit" 
    echo "TK_OPTS    += --enable-64bit" 
    echo "VFS_OPTS   += --enable-64bit" 
    echo "VLERQ_OPTS += --enable-64bit"
    echo "MK_OPTS    += --enable-64bit"
    echo "ITCL_OPTS  += --enable-64bit"
    ;; 
  esac

  #case $verbose in 1) kitopts=" -d" ;; esac
  case $allenc  in 1) kitopts="$kitopts -e" ;; esac
  case $allmsgs in 1) kitopts="$kitopts -m" ;; esac
  case $tzdata  in 1) kitopts="$kitopts -z" ;; esac
  
  case $thread in
    1) case $mach in Linux|SunOS|*BSD)
	       echo "LDFLAGS   += -lpthread" ;;
       esac
       echo "TCL_OPTS   = --enable-threads"
       echo "KITDEPS    = build/threaddyn"
       echo "KIT_OPTS   = -t$kitopts" ;;
    0) echo "KIT_OPTS   =$kitopts" ;;
  esac
  
  case $plat in win) echo "TCL_OPTS  += --with-encoding=utf-8" ;; esac
  case $tzdata in 1) echo "TCL_OPTS  += --with-tzdata" ;; esac

  case $gprof in 1) 
    echo "CFLAGS    += -pg"
    sym=1 ;; 
  esac

  case $gcov in 1) 
    echo "CFLAGS    += -fprofile-arcs -ftest-coverage -O0"
    echo "LDFLAGS   += -lgcov"
    sym=1 ;; 
  esac

  case $sym in 1)
    echo "STRIP      = :"
    echo
    echo "TCL_OPTS       += --enable-symbols"
    echo "THREADDYN_OPTS += --enable-symbols"
    echo "TK_OPTS        += --enable-symbols"
    echo "TKDYN_OPTS     += --enable-symbols"
    echo "VFS_OPTS       += --enable-symbols"
    echo "VLERQ_OPTS     += --enable-symbols"
    echo "MK_OPTS        += --enable-symbols"
    echo "ITCL_OPTS      += --enable-symbols"
    echo ;;
  esac
  
  case $cli in 1) targets="$targets tclkit-cli" ;; esac
  case $dyn in 1) targets="$targets tclkit-dyn" ;; esac
  case $gui in 1) targets="$targets tclkit-gui" ;; esac
  case $mk in 
    1)  case $cli in 1) targets="$targets tclkitsh" ;; esac
        # On Windows the old-style tclkit has Tk linked in statically, which
        # cannot share a build area with the shared Tk of tclkit-dyn: it is
        # only built together with "gui" there.
        case $dyn-$plat in 1-unix) targets="$targets tclkit" ;; esac
        case $gui in 1) targets="$targets tclkit" ;; esac
        ;; 
  esac

  case $thread in
    1) echo "all: threaded$targets" ;;
    0) echo "all:$targets" ;;
  esac

  case $mach in MINGW*)
    echo
    echo "tclkit-cli: tclkit-cli.exe"
    echo "tclkit-dyn: tclkit-dyn.exe"
    echo "tclkit-gui: tclkit-gui.exe"
    case $mk in 1) echo "tclkitsh: tclkitsh.exe"
                   echo "tclkit: tclkit.exe" ;;
    esac
  esac
  
  echo
  case $ext in ?*) echo "KITEXT     = $ext"; echo ;; esac
  echo "include ../../makefile.include"
  
) >$make

case $verbose in 1)
  echo
  echo "Contents of $make:"
  echo "======================================================================="
  cat $make
  echo "======================================================================="
  echo
  echo "To build, run these commands:"
  echo "    cd $path"
  echo "    make"
  echo
  echo "This produces the following executable(s):"
  case $cli in 1) echo "    $path/tclkit-cli   (command-line)" ;; esac
  case $dyn in 1) echo "    $path/tclkit-dyn   (Tk as shared lib)" ;; esac
  case $gui in 1) echo "    $path/tclkit-gui   (Tk linked statically)" ;; esac
  case $mk in 1)
      case $cli in 1) echo "    $path/tclkitsh     (old-style command line)" ;; esac
      case $dyn in 1) echo "    $path/tclkit       (old-style with Tk)" ;; esac
      case $gui in 1) echo "    $path/tclkit       (old-style with Tk)" ;; esac
      ;;
  esac
  echo
  echo "To remove all intermediate builds, use 'make clean'."
  echo "To remove all executables as well, use 'make distclean'."
  echo
esac
