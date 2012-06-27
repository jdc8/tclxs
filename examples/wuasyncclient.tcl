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

proc get_weather {} {
    global total_temp cnt done
    set data [subscriber recv]
    puts $data
    lassign $data zipcode temperature relhumidity
    incr total_temp $temperature
    incr cnt
    if {$cnt >= 10} {
	set done 1
    }
}

subscriber setsockopt SUBSCRIBE $filter
set total_temp 0
set cnt 0
subscriber readable get_weather

# Process updates
vwait done

puts "Averate temperatur for zipcode $filter was [expr {$total_temp/$cnt}]F"

subscriber destroy
context destroy
