#########################################################
# Title; expect-brew
# Description; Calls and accepts the Homebrew installer
# Credits; Diego Iaconelli
# Source; https://github.com/matdotcx/
# Initial Version; Sun Oct 25 12:18:42 GMT 2015
#########################################################

#!/usr/bin/expect -f
# vim: sw=4:et:ft=expect:fdm=indent

set timeout -1
log_user 0
spawn install_brew.sh
match_max 100000

expect {
	"Press RETURN to continue or any other key to abort" }
	send -- "\r"
	exit
}
