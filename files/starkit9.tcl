# starkit9.tcl -- minimal "starkit" package for the zipfs based Tcl 9 tclkit
#
# Lets the usual application preamble keep working unchanged:
#
#     package require starkit
#     starkit::startup
#     ... use $starkit::topdir ...
#
# starkit::startup returns
#     starpack    main.tcl is inside the executable itself
#     starkit     main.tcl is inside a zip archive run by a tclkit
#     sourced     the calling script was sourced by another script
#     unwrapped   main.tcl is a plain file on disk

package provide starkit 1.3.3

namespace eval ::starkit {
  variable topdir
  variable mode
}

proc ::starkit::startup {} {
  variable topdir
  variable mode

  set script [file normalize [info script]]
  set topdir [file dirname $script]
  set root [zipfs root]

  if {$script eq "${root}app/main.tcl"} {
    set mode starpack
  } elseif {[info exists ::tclkit::topdir]
      && $script eq "$::tclkit::topdir/main.tcl"} {
    set mode starkit
  } elseif {[info exists ::argv0] && [file normalize $::argv0] ne $script} {
    set mode sourced
  } else {
    set mode unwrapped
  }
  autoextend [file join $topdir lib]
  return $mode
}

# append an entry to auto_path, if it is a directory and not yet listed
proc ::starkit::autoextend {dir} {
  global auto_path
  set dir [file normalize $dir]
  if {[file isdirectory $dir] && $dir ni $auto_path} {
    lappend auto_path $dir
  }
}
