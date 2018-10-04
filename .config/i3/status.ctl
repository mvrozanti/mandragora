#!/bin/tclsh
package require http
::http::config -useragent "Mozilla/5.0 (X11; Linux i686; rv:24.0) Gecko/20100101 Firefox/24.0"
set    red "#FF0000"
set  green "#00FF00"
set yellow "#FFF000"
set   blue "#00EAFF" 
set  white "#FFFFFF" 
puts {{"version":1}
[
[]}
#proc dropbox {} {
#    catch { exec dropbox status} msg 
#    set dropbox $msg
#    if {$dropbox=="Dropbox isn't running!" || [string match Connecting* $dropbox]} {
#        set stdout {{"name":"dropbox","full_text":"IDLE","color": "$::red"}}
#    } else {
#        set dropbox [string toupper $dropbox 0 end]
#        regsub -all {\.\.\.} $dropbox " " dropbox 
#        set dropbox [split $dropbox " "]
#        set dropbox [lindex $dropbox 0] 
#        set dropbox [string range $dropbox 0 3]
#        if {$dropbox=="UP"} {set dropbox "IDLE"}
#        set stdout {{"name":"dropbox","full_text":"$dropbox","color": "$::green"}}
#    }
#    set stdout [subst -nocommands $stdout]
#    puts -nonewline $stdout
#}
#proc wifi {} {
#    set hostname [exec hostname]
#    if {$hostname=="R730"} {set con "wlp2s0"} else {set con "wlp3s0"}
#    set wifi [exec iwconfig $con | sed -ne /Point/p | awk {{print $6}}]
#    if {[string match *Not-Associated* $wifi] } {
#        set stdout {{"name":"wifi","full_text":"WIFI","color": "$::red"}} 
#    } else { 
#        set stdout {{"name":"wifi","full_text":"WIFI","color": "$::green"}}
#    }
#    set stdout ...
