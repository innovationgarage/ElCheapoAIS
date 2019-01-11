#! /bin/bash

source /etc/elcheapoais/config
source <(/usr/local/bin/elcheapo-calibrate.sh)

while : ; do
    LOG="/var/log/elcheapoais/ais.$(date +%Y-%m-%dT%H:%M).log"
    echo "Using device with serial $SERIAL..." > "$LOG"
    rtl_ais -n -T -P 1221 -p $PPM -g 60 -S 60  &>> "$LOG"
    sleep 1
done
