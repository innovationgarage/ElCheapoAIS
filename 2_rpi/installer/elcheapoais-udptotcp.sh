#! /bin/bash

source /etc/elcheapoais/config

while : ; do
    LOG="/var/log/elcheapoais/udptotcp.$(date +%Y-%m-%dT%H:%M).log"
    nc -luk 127.0.0.1 1221 | nc -lk 127.0.0.1 1222 > "$LOG" 2>&1
    sleep 1
done
