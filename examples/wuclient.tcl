#
# Weather update client
# Connects SUB socket to tcp:#localhost:5556
# Collects weather updates and finds avg temp in zipcode
#

package require xs

# Socket to talk to server
xs context context
xs socket subscriber context SUB
subscriber connect "tcp://localhost:5556"

# Subscribe to zipcode, default is NYC, 10001
if {[llength $argv]} {
    set filter [lindex $argv 0]
} else {
    set filter "10001"
}

subscriber setsockopt SUBSCRIBE $filter

# Process updates
set total_temp 0
for {set update_nbr 0} {$update_nbr < 10} {incr update_nbr} {
    xs message msg
    subscriber recvmsg msg
    lassign [msg data] zipcode temperature relhumidity
    puts [msg data]
    msg close
    incr total_temp $temperature
}

puts "Averate temperatur for zipcode $filter was [expr {$total_temp/$update_nbr}]F"

subscriber destroy
context destroy
