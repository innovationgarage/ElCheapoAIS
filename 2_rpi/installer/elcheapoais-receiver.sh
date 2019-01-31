#! /bin/bash

source /etc/elcheapoais/config
source <(/usr/local/bin/elcheapo-calibrate.sh)

while : ; do
    LOG="/var/log/elcheapoais/ais.$(date +%Y-%m-%dT%H:%M).log"
    {
      echo "Using device with serial $SERIAL..."
      echo "Running rtl_ais -n -h 127.0.0.1 -P 1221 -p $PPM"
      rtl_ais -n -h 127.0.0.1 -P 1221 -p $PPM 2>&1
    } > "$LOG"
    sleep 1
done
