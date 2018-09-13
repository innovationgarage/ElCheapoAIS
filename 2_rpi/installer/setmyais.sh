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
	WT_MENU_HEIGHT=$(($WT_HEIGHT - 7))
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
		--yes-button Install --no-button Cancel
	RET=$?
	if [ $RET -eq 0 ]; then
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
	freq="850"
	freq=$(whiptail --inputbox "Input the base frequency for the calibration routine (850, 900, etc) in MHz" 20 60 "$freq" 3>&1 1>&2 2>&3)
	if [ $? -eq 1 ]; then
		return 1
	fi

	kal -g 42 -e 22 -s $freq 2>&1 | tee stations.txt
	chan="$(cat stations.txt | sed -n 's/.*chan: \(.*\) (.*power: \(.*\)/\2 \1/p' | sort | tail -n 1 | {
		read a b
		echo $b
	})"
	echo "Using channel $chan"
	kal -e 41 -c $chan -v | tee calibration.txt
	cat calibration.txt | sed -n "s/average absolute error: \(.*\) ppm/\1/p" >ppm_error.txt
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

do_install() {
	# TODO: Clean variables
	server="127.0.0.1"
	server=$(whiptail --inputbox "UDP server address" 20 60 "$server" 3>&1 1>&2 2>&3)
	if [ $? -eq 1 ]; then
		return 1
	fi

	port="2222"
	port=$(whiptail --inputbox "UDP server port" 20 60 "$port" 3>&1 1>&2 2>&3)
	if [ $? -eq 1 ]; then
		return 1
	fi

	ppm="$([ -r ppm_error.txt ] && cat ppm_error.txt || echo 0)"

	# TODO: Validate IP and port
	cat <<EOF >/tmp/cheapoais
while :
do
sudo rtl_ais -n -h $server -P $port -p $ppm -g 60 -S 60  &> "/var/log/cheapoais/ais.\$(date +%Y-%m-%d_%H-%M).log"
sleep 1
done
EOF

	sudo mkdir -p /var/log/cheapoais
	sudo mv /tmp/cheapoais /usr/local/bin/
	chmod a+x /usr/local/bin/cheapoais

	# Configure systemd

	cat <<EOF >/tmp/cheapoais.service
[Unit]
Description=CheapoAIS Service
After=multi-user.target

[Service]
Type=idle
ExecStart=/bin/bash /usr/local/bin/cheapoais
KillMode=process
Type=forking

[Install]
WantedBy=multi-user.target
EOF
	sudo mv /tmp/cheapoais.service /lib/systemd/system/
	sudo chmod 644 /lib/systemd/system/cheapoais.service

	sudo systemctl daemon-reload
	sudo systemctl enable cheapoais.service

	ASK_TO_REBOOT=1
	whiptail --msgbox "\
Setup done. To start service reboot or execute:
sudo systemctl start cheapoais.service

Check logs here:
/var/log/cheapoais/
" 20 70 1

	return 0
}

do_test_run() {
	ppm="$([ -r ppm_error.txt ] && cat ppm_error.txt || echo 0)"
	whiptail --yesno "The program is going to execute rtl_ais now so you can check if you are able to receive NMEA sentences to the console.\n\nThe average absolute error $ppm ppm.\n(If that value is incorrect, cancel and run the calibration again)" 20 60 2 \
		--yes-button Cancel --no-button Run
	RET=$?
	if [ $RET -eq 1 ]; then
		sudo rtl_ais -n -p $ppm -g 60 -S 60
	fi
	return 0
}

do_advanced_menu2() {
	FUN=$(whiptail --title "ElCheapoAIS configuration tools" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
		"1 Calibrate" "Find the error ppm" \
		"2 Test run" "Run rtl_ais (using the error ppm parameter from step 1)" \
		"3 Re-install" "Configure rtl_ais to run at system boot" \
		"4 Remove" "Remove rtl_ais from system boot" \
		"A About ElCheapoAIS" "Information about this tool" \
		3>&1 1>&2 2>&3)
	RET=$?
	if [ $RET -eq 1 ]; then
		do_finish
	elif [ $RET -eq 0 ]; then
		case "$FUN" in
		1\ *) do_calibrate ;;
		2\ *) do_test_run ;;
		3\ *) do_install ;;
		4\ *) do_remove ;;
		A\ *) do_about ;;
		*) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
		esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
	fi
}

do_advanced_menu() {
	FUN=$(whiptail --title "ElCheapoAIS configuration tools" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
		"1 Calibrate" "Find the error ppm" \
		"2 Test run" "Run rtl_ais (using the error ppm parameter from step 1)" \
		"3 Install" "Configure rtl_ais to run at system boot" \
		"A About ElCheapoAIS" "Information about this tool" \
		3>&1 1>&2 2>&3)
	RET=$?
	if [ $RET -eq 1 ]; then
		do_finish
	elif [ $RET -eq 0 ]; then
		case "$FUN" in
		1\ *) do_calibrate ;;
		2\ *) do_test_run ;;
		3\ *) do_install ;;
		A\ *) do_about ;;
		*) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
		esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
	fi
}

#
# Interactive use loop
#
calc_wt_size
while true; do
	if [ -x "$(command -v kal)" ] && [ -x "$(command -v rtl_ais)" ]; then
		do_advanced_menu
	else
		FUN=$(whiptail --title "ElCheapoAIS configuration tools" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
			"0 Prepare system" "Download, compile and install required components" \
			"A About ElCheapoAIS" "Information about this tool" \
			3>&1 1>&2 2>&3)
		RET=$?
		if [ $RET -eq 1 ]; then
			do_finish
		elif [ $RET -eq 0 ]; then
			case "$FUN" in
			0\ *) do_system_prepare ;;
			A\ *) do_about ;;
			*) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
		else
			exit 1
		fi
	fi
done
