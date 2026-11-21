#!/usr/bin/env tclsh
# Put the current docs.css into the HTML documents.
#
#   usage: tclsh mkdocs.tcl
#
# The documents are meant to be readable as single files (the download area
# lists them on their own), so each one carries the style sheet inline,
# between the two marker comments. Edit docs.css, then run this again.

set dir [file dirname [info script]]
set fd [open [file join $dir docs.css]]
set css [string trim [read $fd]]
close $fd

set begin "<!-- docs.css -->"
set end   "<!-- /docs.css -->"
set block "$begin\n<style type=\"text/css\">\n$css\n</style>\n$end"

foreach doc {HOWTOUSE.HTML HOWTOUSE9.HTML HOWTOBUILD.HTML} {
  set path [file join $dir $doc]
  set fd [open $path]
  fconfigure $fd -encoding utf-8 -translation lf
  set html [read $fd]
  close $fd

  set a [string first $begin $html]
  set b [string first $end $html]
  if {$a >= 0 && $b > $a} {
    # replace the block of an earlier run
    set b [expr {$b + [string length $end] - 1}]
  } elseif {[regexp -indices {<link rel="stylesheet" href="docs.css"[^>]*>} \
      $html range]} {
    # first run: replace the link to the style sheet
    lassign $range a b
  } else {
    puts stderr "$doc: no style sheet link or block found"
    continue
  }
  set html [string replace $html $a $b $block]

  set fd [open $path w]
  fconfigure $fd -encoding utf-8 -translation lf
  puts -nonewline $fd $html
  close $fd
  puts "$doc: updated"
}
