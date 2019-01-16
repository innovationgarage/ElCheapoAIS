#! /bin/bash

source /etc/elcheapoais/config

FIFO=/tmp/udptotcpfifo
mkfifo $FIFO

while : ; do
    nc -luk localhost 1221 < $FIFO | nc -lk localhost 1222 > $FIFO
    sleep 1
done
