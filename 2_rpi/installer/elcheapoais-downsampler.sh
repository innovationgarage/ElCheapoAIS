#! /bin/bash

source /etc/elcheapoais/config
source <(/usr/local/bin/elcheapo-calibrate.sh)

while : ; do
    LOG="/var/log/elcheapoais/downsampler.$(date +%Y-%m-%dT%H:%M).log"
    aisdownsampler server \
      --station-id "$stationid" \
      --max-message-per-sec $msgspersec \
      --max-message-per-mmsi-per-sec $msgspersecpermmsi \
      '{"type": "connect", "connect":"tcp:localhost:1222"}' \
      '{"type": "connect", "connect":"'"tcp:$server:$port"'"}' > "$LOG" 2>&1
done
