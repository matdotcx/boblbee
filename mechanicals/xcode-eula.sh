#########################################################
# Title; xcode-eula
# Description; Call and accept the Xcode EULA
# Credits; Diego Iaconelli
# Source; https://github.com/matdotcx/
# Initial Version; Sun Oct 25 12:17:57 GMT 2015
#########################################################


#!/usr/bin/expect -f
# vim: sw=4:et:ft=expect:fdm=indent
 
set timeout -1
log_user 0
spawn sudo xcodebuild -license
match_max 100000
expect {
    "Hit the Enter key" {
	send -- "\r"
	exp_continue
    }
    "Press 'space' for more, or 'q' to quit" {
	send -- "q"
	exp_continue
    }
    "agree, print, cancel" {
	send -- "agree\r"
	exp_continue
    }
    eof {
	send_user "EULA accepted.\n"
	exit
    }
}