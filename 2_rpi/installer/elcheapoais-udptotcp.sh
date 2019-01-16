#! /bin/bash

source /etc/elcheapoais/config

while : ; do
    nc -luk localhost 1221 | nc -lk localhost 1222
    sleep 1
done
