#! /bin/bash

sudo apt install -y git

git clone git@github.com:innovationgarage/ElCheapoAIS.git
cd ElCheapoAIS/2_rpi/installer
sudo ./setmyais.sh
