# setupvfs9.tcl -- fill the zip archive of a Tcl 9 tclkit and attach it
#
# Run by the freshly linked kit-cli from a 9.x build directory:
#
#   TCL_LIBRARY=../tcl/library ./kit-cli ../../setupvfs9.tcl \
#       ?-d? ?-e? ?-m? ?-z? ?-c path? destfile rawexe (cli|dyn|gui)
#
#   -d        output some debugging info
#   -e        include all encodings i.s.o. the basic set
#   -m        include the localized message catalogs of Tcl
#   -z        include the timezone data files
#   -c path   source a custom script for additional setup ($vfs is the tree)
#
# The archive layout is the one the Tcl 9 core expects in an executable:
#
#   tcl_library/   Tcl script library
#   tk_library/    Tk script library                       (gui)
#   lib/           packages: static extensions, Tk dll (dyn), starkit
#
# An application adds main.tcl on top of that, see README.md.

set debugOpt 0
set encOpt 0
set msgsOpt 0
set tzOpt 0
set customOpt {}

while {1} {
  switch -- [lindex $argv 0] {
    -d { incr debugOpt }
    -e { incr encOpt }
    -m { incr msgsOpt }
    -z { incr tzOpt }
    -c {
      set customOpt [lindex $argv 1]
      set argv [lrange $argv 1 end]
    }
    default { break }
  }
  set argv [lrange $argv 1 end]
}

if {[llength $argv] != 3} {
  puts stderr "Usage: [file tail [info nameofexe]] [info script]\
    ?-d? ?-e? ?-m? ?-z? ?-c path? destfile rawexe (cli|dyn|gui)"
  exit 1
}
lassign $argv dest rawexe type

proc debug {msg} {
  if {$::debugOpt} { puts $msg }
}

# copy a file or a whole tree, skipping editor and VCS leftovers
proc copy {src dst} {
  if {[file isdirectory $src]} {
    file mkdir $dst
    foreach f [glob -nocomplain -directory $src -tails *] {
      copy $src/$f $dst/$f
    }
    return
  }
  set tail [file tail $src]
  if {[string match *~ $tail] || [string match .#* $tail]} return
  file mkdir [file dirname $dst]
  file copy -force $src $dst
}

# package index for an extension linked statically into the executable
proc staticpkg {name {prefix {}} {files {}}} {
  global vfs
  if {$prefix eq ""} { set prefix $name }
  load {} $prefix
  set ver [package provide $name]
  set dir $vfs/lib/[string tolower $name]$ver
  file mkdir $dir
  set script "load {} $prefix"
  foreach f $files {
    copy $f $dir/[file tail $f]
    append script "; source \[file join \$dir [file tail $f]\]"
  }
  set fd [open $dir/pkgIndex.tcl w]
  fconfigure $fd -translation lf
  puts $fd "package ifneeded $name $ver \[list apply {dir {$script}} \$dir\]"
  close $fd
  debug "  static $name $ver"
}

set vfs [file normalize build/vfs-$type]
file delete -force $vfs
file mkdir $vfs/lib

# Every interpreter (child, thread) starts with the directory above
# tcl_library on its auto_path, i.e. the archive root, and so finds this
# index. It adds lib/ itself to the path, which makes the package search
# descend into lib/*/ as applications expect.
set fd [open $vfs/lib/pkgIndex.tcl w]
fconfigure $fd -translation lf
puts $fd {if {$dir ni $::auto_path} { lappend ::auto_path $dir }}
close $fd

# --- Tcl library -----------------------------------------------------------

set tcllib $vfs/tcl_library
foreach f [glob -directory ../tcl/library -tails *] {
  switch -- $f {
    dde - registry { continue }
    encoding { if {!$encOpt} continue }
    msgs     { if {!$msgsOpt} continue }
    tzdata   { if {!$tzOpt} continue }
  }
  copy ../tcl/library/$f $tcllib/$f
}
# same as the stock build: the manifest doubles as package index
file copy -force $tcllib/manifest.txt $tcllib/pkgIndex.tcl

if {!$encOpt} {
  # the basic set of the 8.x kits; anything else needs the "allenc" option
  foreach e {
    ascii cp1250 cp1251 cp1252 cp1253 cp1254 cp1255 cp1256 cp1257 cp1258
    cp437 cp737 cp775 cp850 cp852 cp855 cp857 cp860 cp861 cp862 cp863
    cp864 cp865 cp866 cp869 cp874 cp932 cp949 euc-kr
    iso2022 iso2022-jp iso2022-kr iso8859-1 iso8859-10 iso8859-13
    iso8859-14 iso8859-15 iso8859-16 iso8859-2 iso8859-3 iso8859-4
    iso8859-5 iso8859-6 iso8859-7 iso8859-8 iso8859-9 jis0201
    dingbats ebcdic gb1988 koi8-r koi8-u macCentEuro macCroatian
    macCyrillic macDingbats macGreek macIceland macRoman macRomania
    macThai macTurkish macUkraine symbol tis-620
  } {
    if {[file exists ../tcl/library/encoding/$e.enc]} {
      copy ../tcl/library/encoding/$e.enc $tcllib/encoding/$e.enc
    }
  }
}

# --- static extensions -----------------------------------------------------

foreach ext {Registry Dde} name {registry dde} {
  if {![catch {load {} $ext}]} {
    set dir $vfs/lib/$name
    file mkdir $dir
    set fd [open $dir/pkgIndex.tcl w]
    fconfigure $fd -translation lf
    puts $fd "package ifneeded $name [package provide $name] {load {} $ext}"
    close $fd
  }
}

set loaded {}
foreach item [info loaded] { lappend loaded [lindex $item 1] }

if {"Thread" in $loaded} {
  staticpkg Thread
  # ttrace is a pure Tcl companion of the Thread package
  set tt [lindex [glob -nocomplain ../tcl/pkgs/thread*/lib/ttrace.tcl] end]
  if {$tt ne ""} {
    copy $tt $vfs/lib/ttrace/ttrace.tcl
    set fd [open $tt]
    regexp {package provide Ttrace ([0-9.ab]+)} [read $fd] -> ttver
    close $fd
    set fd [open $vfs/lib/ttrace/pkgIndex.tcl w]
    fconfigure $fd -translation lf
    foreach n {Ttrace ttrace} {
      puts $fd "package ifneeded $n $ttver\
        \[list source \[file join \$dir ttrace.tcl\]\]"
    }
    close $fd
  }
}
if {"Itcl" in $loaded} {
  # Loading Itcl needs its script library, which is not installed anywhere
  # at this point, so take the version from the source directory instead.
  # Itcl looks for its scripts in itcl<patchlevel> next to tcl_library.
  set src [lindex [lsort -dictionary [glob ../tcl/pkgs/itcl*/library]] end]
  regexp {itcl([0-9.ab]+)$} [file dirname $src] -> ver
  foreach f [glob -nocomplain $src/*.tcl] {
    copy $f $vfs/itcl$ver/[file tail $f]
  }
  set dir $vfs/lib/itcl$ver
  file mkdir $dir
  set fd [open $dir/pkgIndex.tcl w]
  fconfigure $fd -translation lf
  foreach n {itcl Itcl} {
    puts $fd "package ifneeded $n $ver {load {} Itcl}"
  }
  close $fd
  debug "  static itcl $ver"
}
if {"Sqlite3" in $loaded} {
  staticpkg sqlite3 Sqlite3
}

# --- starkit compatibility -------------------------------------------------

copy ../../files/starkit9.tcl $vfs/lib/starkit/starkit.tcl
set fd [open $vfs/lib/starkit/pkgIndex.tcl w]
fconfigure $fd -translation lf
puts $fd "package ifneeded starkit 1.3.3\
  \[list source \[file join \$dir starkit.tcl\]\]"
close $fd

# --- wrap: "tclkit -wrap out appdir" -----------------------------------------

copy ../../files/wrap9.tcl $vfs/lib/tclkit/wrap.tcl
set fd [open $vfs/lib/tclkit/pkgIndex.tcl w]
fconfigure $fd -translation lf
puts $fd "package ifneeded tclkit::wrap 1.0\
  \[list source \[file join \$dir wrap.tcl\]\]"
close $fd

# --- Tk --------------------------------------------------------------------

switch -- $type {
  cli {}
  gui - dyn {
    foreach f [glob -directory ../tk/library -tails *] {
      if {$f eq "demos"} continue
      copy ../tk/library/$f $vfs/tk_library/$f
    }
  }
}

switch -- $type {
  cli - gui {}
  dyn {
    set dll [lindex [glob build/tkdyn/*tk*[info sharedlibextension]] 0]
    set fd [open ../tk/generic/tk.h]
    regexp {define\s+TK_PATCH_LEVEL\s+"([^"]+)"} [read $fd] -> tkver
    close $fd
    set dir $vfs/lib/tk$tkver
    file mkdir $dir

    # The shared Tk library has its own copy of the script library attached
    # as a zip archive. Tk does not find it there once the dll is loaded out
    # of our archive (Tcl loads a temporary copy), so the scripts are in
    # tk_library above and the attached copy is cut off to save space.
    set size [file size $dll]
    catch {
      zipfs mount $dll [zipfs root]kit-tkdll
      set size [lindex [zipfs info [zipfs root]kit-tkdll] 3]
      zipfs unmount [zipfs root]kit-tkdll
    }
    set in [open $dll rb]
    set out [open $dir/[file tail $dll] wb]
    fcopy $in $out -size $size
    close $in
    close $out
    debug "  [file tail $dll]: $size of [file size $dll] bytes"

    set fd [open $dir/pkgIndex.tcl w]
    fconfigure $fd -translation lf
    foreach n {tk Tk} {
      puts $fd "package ifneeded $n $tkver\
        \[list load \[file join \$dir [file tail $dll]\] Tk\]"
    }
    close $fd
    debug "  dynamic Tk $tkver ([file tail $dll])"
  }
  default {
    puts stderr "Unknown type, must be one of: cli, dyn, gui"
    exit 1
  }
}

if {$customOpt ne {}} {
  source $customOpt
}

# --- attach ----------------------------------------------------------------

file delete -force $dest
zipfs mkimg $dest $vfs $vfs "" $rawexe

debug "Done: $dest ([file size $dest] bytes)"
