# kitext.tcl -- custom vfs setup script for tclkit-gui with static packages
#
# Sourced by setupvfs.tcl / setupvfs9.tcl (-c) when config.sh was given
# ext=dir: copies the tree dir/vfs/ into the kit, so that the script side of
# the packages linked into the executable (pkgIndex.tcl, library scripts)
# is found under lib/ like the packages the kit carries itself. The
# directory comes from the environment variable KIT_EXT.
#
# $vfs is the root of the kit being written: the mounted executable (8.x)
# or the directory that is zipped into it (9.x).

proc kitext_copy {src dst} {
  if {[file isdirectory $src]} {
    file mkdir $dst
    foreach f [glob -nocomplain -directory $src -tails *] {
      kitext_copy [file join $src $f] [file join $dst $f]
    }
    return
  }
  set tail [file tail $src]
  if {[string match *~ $tail] || [string match .#* $tail]} return
  file copy -force $src $dst
}

if {![info exists env(KIT_EXT)] || $env(KIT_EXT) eq ""} {
  puts stderr "kitext.tcl: KIT_EXT is not set"
  exit 1
}
set kitext_src [file join $env(KIT_EXT) vfs]
if {[file isdirectory $kitext_src]} {
  foreach f [glob -nocomplain -directory $kitext_src -tails *] {
    kitext_copy [file join $kitext_src $f] [file join $vfs $f]
    puts "  added $f/ from $kitext_src"
  }
}
