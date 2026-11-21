# validate9.tcl -- basic build validation for the Tcl 9 tclkit
#
# Check that the library is found inside the executable and that the static
# packages load in the main, child and thread interpreters.

puts "version : Tcl [info patchlevel] $tcl_platform(osVersion) $tcl_platform(machine)"
puts "library : [info library]"

if {![string match [zipfs root]* [info library]]} {
  error "the Tcl library is not inside the executable"
}

set ext {starkit}
if {$tcl_platform(platform) eq "windows"} { lappend ext registry dde }
foreach pkg {Thread itcl sqlite3} {
  if {![catch {package require $pkg}]} { lappend ext $pkg }
}

set r {}
foreach pkg $ext { lappend r $pkg [package require $pkg] }
puts "main    : $r"

interp create child
set r {}
foreach pkg $ext { lappend r $pkg [child eval [list package require $pkg]] }
puts "child   : $r"

if {"Thread" in $ext} {
  set tid [thread::create]
  set r {}
  foreach pkg $ext {
    lappend r $pkg [thread::send $tid [list package require $pkg]]
  }
  thread::release $tid
  puts "thread  : $r"
}

# encodings and clock need files from the archive
encoding convertto cp1252 abc
clock format 0 -gmt 1
puts "encoding: [llength [encoding names]] available, system [encoding system]"
