#########################################################
# Title; uptime
# Description; Fancy uptime script for bash & zsh prompt
# Source; https://github.com/matdotcx/
#########################################################

#!/bin/bash

NOW=$(date "+%s")
BOOTTIME=$(sysctl -n kern.boottime | cut -c9-18)
UPTIME=$(expr $NOW - $BOOTTIME)

d=0
h=0
m=0
s=0

while [ $UPTIME -gt 86399 ]; do
        d=$(expr $d + 1)
        UPTIME=$(expr "$UPTIME" - 86400)
done

while [ $UPTIME -gt 3599 ]; do
        h=$(expr $h + 1)
        UPTIME=$(expr "$UPTIME" - 3600)
done

while [ $UPTIME -gt 59 ]; do
        m=$(expr $m + 1)
        UPTIME=$(expr "$UPTIME" - 60)
done

s=$UPTIME

dText="day"
hText="hour"
mText="minute"
sText="second"

if [ $d -ne 1 ]; then
        dText="days"
fi

if [ $h -ne 1 ]; then
        hText="hours"
fi

if [ $m -ne 1 ]; then
        mText="minutes"
fi

if [ $s -ne 1 ]; then
        sText="seconds"
fi

echo "System Uptime: $d $dText, $h $hText, $m $mText, and $s $sText"
