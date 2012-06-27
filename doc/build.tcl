package require doctools

set on [doctools::new on -format html]
set f [open xs.html w]
puts $f [$on format {[include xs.man]}]
close $f

$on destroy
