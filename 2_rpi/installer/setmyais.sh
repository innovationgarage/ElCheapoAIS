#!/bin/sh
# Based on raspi-config https://github.com/asb/raspi-config
# See LICENSE file for copyright and license details

INTERACTIVE=True
ASK_TO_REBOOT=0

calc_wt_size() {
  # NOTE: it's tempting to redirect stderr to /dev/null, so supress error 
  # output from tput. However in this case, tput detects neither stdout or 
  # stderr is a tty and so only gives default 80, 24 values
  WT_HEIGHT=17
  WT_WIDTH=$(tput cols)

  if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
    WT_WIDTH=80
  fi
  if [ "$WT_WIDTH" -gt 178 ]; then
    WT_WIDTH=120
  fi
  WT_MENU_HEIGHT=$(($WT_HEIGHT-7))
}

do_about() {
  whiptail --msgbox "\
This configurator makes setting up a Raspberry Pi Marine
AIS server fast and simple. You only need a cheap dongle
that uses the rtl2832U chip and a proper antenna.\
" 20 70 1
}

do_system_prepare() {

  whiptail --yesno "The script is going to compile and install kalibrate-rtl and rtl-ais\n\nDo you want to continue?" 20 60 2 \
    --yes-button Cancel --no-button Install
  RET=$?
  if [ $RET -eq 0 ] 
  then
    return 0
  fi
  
# General dependencies
  echo Installing dependencies
  apt install build-essential libtool m4 automake libfftw3-dev automake autoconf git librtlsdr-dev libusb-dev libpthread-workqueue-dev -y

# kalibrate-rtl
  echo Downloading kalibrate-rtl
  git clone https://github.com/steve-m/kalibrate-rtl
  cd kalibrate-rtl
  
  echo Installing... 
  sudo ./bootstrap && CXXFLAGS='-W -Wall -O3'
  sudo ./configure
  make
  sudo make install

# rtl-ais
  echo Downloading rtl-ais
  cd ..
  git clone https://github.com/dgiardini/rtl-ais 		
  cd rtl-ais
  
  echo Installing...
  make
  cp rtl_ais /usr/bin

  if [ "$INTERACTIVE" = True ]; then
    whiptail --msgbox "Your system is ready.\nConfigure your station from the main menu" 20 60 2
  fi
}

do_finish() {
  if [ $ASK_TO_REBOOT -eq 1 ]; then
    whiptail --yesno "Would you like to reboot now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  fi
  exit 0
}

# Everything else needs to be run as root
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root.\n"
  exit 1
fi


do_calibrate() {
  kal -g 42 -e 22 -s 850
  return 0
}

do_reset() {
  git clone https://github.com/codazoda/hub-ctrl.c
   cd hub-ctrl.c
   gcc -o hub-ctrl hub-ctrl.c -lusb
   cp hub-ctrl ..
   cd ..
   echo "Disconnecting devices (you might lose connection for few seconds if this is remote)"
   sudo ./hub-ctrl -h 0 -P 2 -p 0
   sleep 5
   sudo ./hub-ctrl -h 0 -P 2 -p 1
   echo done
   sleep 1
   return 0
}


do_test_run() {
  rtl_ais
  return 0
}

do_advanced_menu() {
  FUN=$(whiptail --title "ElCheapoAIS configuration tools" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
      "1 Calibrate" "Find the error ppm" \
      "2 Test run" "Run rtl_ais (using the error ppm parameter)" \
      "3 Configure" "Configure rtl_ais to run at system boot" \
      "4 Remove" "Remove all components" \
            "5 Reset USB" "Reset the USB devices (in case the rtl-sdr is not responding)" \
      "6 About ElCheapoAIS" "Information about this tool" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      1\ *) do_calibrate ;;
      2\ *) do_test_run ;;
      3\ *) do_memory_split ;;
      4\ *) do_ssh ;;
      5\ *) do_reset ;;      
      6\ *) do_about ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  fi
}

#
# Interactive use loop
#
calc_wt_size
if [ -x "$(command -v kal)" ] && [ -x "$(command -v rtl_ais)" ]; then
  do_advanced_menu
else
  while true; do
    FUN=$(whiptail --title "ElCheapoAIS configuration tools" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
      "1 Prepare system" "Download, compile and install required components" \
      "2 About ElCheapoAIS" "Information about this tool" \
      3>&1 1>&2 2>&3)
    RET=$?
    if [ $RET -eq 1 ]; then
      do_finish
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        1\ *) do_system_prepare ;;
        2\ *) do_about ;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    else
      exit 1
    fi
  done
fi