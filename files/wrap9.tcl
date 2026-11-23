# wrap9.tcl -- turn an application directory into a kit or an executable
#
# Part of the zipfs based Tcl 9 tclkit, the counterpart of "sdx wrap".
#
#     tclkit -wrap app.kit appdir
#     tclkit -wrap app.exe appdir ?-runtime tclkit-gui.exe? ?-icon app.ico?
#
# appdir holds main.tcl and usually lib/ with the packages of the application.
#
# A target ending in .kit, .zkit or .zip becomes a plain zip archive, to be
# run as "tclkit app.kit". Anything else becomes a standalone executable: the
# runtime (by default the running tclkit) with its own library and the
# application merged into the attached archive. With -icon (Windows only) the
# icons of the executable are replaced by the ones of the .ico file.

package provide tclkit::wrap 1.0

namespace eval ::tclkit::wrap {}

proc ::tclkit::wrap::copy {src dst} {
  if {[file isdirectory $src]} {
    file mkdir $dst
    foreach f [glob -nocomplain -directory $src -tails * .?*] {
      if {$f eq ".."} continue
      copy [file join $src $f] [file join $dst $f]
    }
  } else {
    file mkdir [file dirname $dst]
    file copy -force $src $dst
  }
}

# Copy an executable without the archive attached to it.

proc ::tclkit::wrap::stub {exe dst} {
  set f [open $exe rb]
  try {
    set size [file size $exe]
    set len [expr {min($size, 65557)}]
    chan seek $f -$len end
    set tail [read $f $len]
    set n $size
    # end of central directory record: size and offset of the directory
    set at [string last "PK\x05\x06" $tail]
    if {$at >= 0 && $at + 22 <= $len} {
      binary scan $tail @[expr {$at + 12}]iuiu cdsize cdoff
      set start [expr {$size - $len + $at - $cdsize - $cdoff}]
      if {$start > 0 && $start < $size} { set n $start }
    }
    chan seek $f 0
    set o [open $dst wb]
    try { chan copy $f $o -size $n } finally { close $o }
  } finally {
    close $f
  }
}

proc ::tclkit::wrap::wrap {out appdir {runtime {}} {icon {}}} {
  if {![file isfile [file join $appdir main.tcl]]} {
    error "$appdir: no main.tcl found"
  }
  set appdir [file normalize $appdir]

  if {[string tolower [file extension $out]] in {.kit .zkit .zip}} {
    if {$runtime ne ""} {
      error "-runtime does not apply to a [file extension $out] archive"
    }
    if {$icon ne ""} {
      error "-icon does not apply to a [file extension $out] archive"
    }
    file delete -force $out
    zipfs mkzip $out $appdir $appdir
    return $out
  }

  set self [file normalize [info nameofexecutable]]
  if {$runtime eq ""} { set runtime $self }
  set runtime [file normalize $runtime]
  if {[file normalize $out] eq $runtime} {
    error "cannot overwrite the runtime itself"
  }

  # where the library of the runtime can be read from
  if {$runtime eq $self} {
    set root [zipfs root]app
    set mounted 0
  } else {
    set root [zipfs root]wrap-runtime
    zipfs mount $runtime $root
    set mounted 1
  }

  set tmp [file join [file dirname [file normalize $out]] \
      .wrap-[pid]-[clock clicks]]
  set stub $tmp.exe
  try {
    if {$icon ne ""} {
      if {[info commands ::tclkit::seticon] eq ""} {
        error "-icon is only available on Windows"
      }
      set f [open $icon rb]
      set icodata [read $f]
      close $f
    }
    if {![file isdirectory [file join $root tcl_library]]} {
      error "$runtime: not a tclkit, there is no Tcl library inside"
    }
    # the runtime first, minus an application it may already carry
    foreach f [glob -nocomplain -directory $root -tails *] {
      if {$f eq "main.tcl"} continue
      copy [file join $root $f] [file join $tmp $f]
    }
    copy $appdir $tmp
    file delete -force $out
    set infile $runtime
    if {$icon ne ""} {
      # the icons go into a copy of the bare executable, before the archive
      # is attached: updating resources drops whatever follows the image
      stub $runtime $stub
      ::tclkit::seticon $stub $icodata
      set infile $stub
    }
    zipfs mkimg $out $tmp $tmp "" $infile
    if {$::tcl_platform(platform) ne "windows"} {
      file attributes $out -permissions +x
    }
  } finally {
    file delete -force $tmp $stub
    if {$mounted} { zipfs unmount $root }
  }
  return $out
}

# command line entry, called for "tclkit -wrap ..."; returns the exit code
proc ::tclkit::wrap::main {argv} {
  set runtime {}
  set icon {}
  set args {}
  for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    if {$a eq "-runtime"} {
      set runtime [lindex $argv [incr i]]
    } elseif {$a eq "-icon"} {
      set icon [lindex $argv [incr i]]
    } else {
      lappend args $a
    }
  }
  if {[llength $args] != 2} {
    puts stderr "usage: [file tail [info nameofexecutable]] -wrap\
      outfile appdir ?-runtime tclkit? ?-icon file.ico?"
    return 1
  }
  if {[catch {wrap [lindex $args 0] [lindex $args 1] $runtime $icon} msg]} {
    puts stderr "wrap failed: $msg"
    return 1
  }
  puts "$msg ([file size $msg] bytes)"
  return 0
}
