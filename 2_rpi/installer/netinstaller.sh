#! /bin/bash

sudo apt update
sudo apt install -y git

git clone "https://github.com/innovationgarage/ElCheapoAIS.git"
cd ElCheapoAIS/2_rpi/installer
sudo ./setmyais.sh
