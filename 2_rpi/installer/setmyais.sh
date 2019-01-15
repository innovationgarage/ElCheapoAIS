#! /bin/bash
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
	if [ $RET != 0 ]; then
		return 0
	fi

	# General dependencies
	echo Installing dependencies
	apt install build-essential libtool m4 automake libfftw3-dev automake autoconf git  libusb-dev libpthread-workqueue-dev pkg-config python python-pip python-dev python-setuptools -y
        # librtlsdr-dev rtl-sdr

        # Somehow, setuptools fails to install this dependency of the downsampler
        pip install click-datetime

        echo Downloading librtlsdr
        (
                # Installing from source and pinning version to get around bug where tuner was not found
                cd /tmp
                git clone git@github.com:librtlsdr/librtlsdr.git
                cd librtlsdr
                git checkout v0.5.3
                mkdir build
                cd build
                cmake .. -DINSTALL_UDEV_RULES=ON -DDETACH_KERNEL_DRIVER=ON -DCMAKE_INSTALL_PREFIX=/usr
                make
                make install
        )

	# kalibrate-rtl
	echo Downloading kalibrate-rtl
	(
	        cd /tmp
                git clone https://github.com/steve-m/kalibrate-rtl
                cd kalibrate-rtl

	        echo Installing...
	        sudo ./bootstrap && CXXFLAGS='-W -Wall -O3'
	        sudo ./configure
	        make
	        sudo make install
        )
		
	# rtl-ais
	echo Downloading rtl-ais
	(
	        cd  /tmp
	        git clone https://github.com/dgiardini/rtl-ais
	        cd rtl-ais

	        echo Installing...
	        make
	        cp rtl_ais /usr/bin
        )
	
        # downsampler
        (
                cd /tmp
                git clone https://github.com/innovationgarage/ElCheapoAIS-downsampler.git
                cd ElCheapoAIS-downsampler

                echo Installing...
                python setup.py install
        )
	
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

        ./elcheapo-calibrate.sh
}

do_reset() {
        (
	        cd /tmp
    	        git clone https://github.com/codazoda/hub-ctrl.c
	        cd hub-ctrl.c
	        gcc -o hub-ctrl hub-ctrl.c -lusb
	        cp hub-ctrl /usr/bin/hub-ctrl

      	        echo "Disconnecting devices (you might lose connection for few seconds if this is remote)"
	        sudo hub-ctrl -h 0 -P 2 -p 0
	        sleep 5
	        sudo hub-ctrl -h 0 -P 2 -p 1
	        echo done
	        sleep 1
	        return 0
	)
}

do_install() {
	# TODO: Clean variables
	server="elcheapoais.innovationgarage.tech"
	port="1024"
	stationid="unknown"
        msgspersec="100"
        msgspersecpermmsi="10"

	server=$(whiptail --inputbox "TCP server address to send messages to" 20 60 "$server" 3>&1 1>&2 2>&3)
	if [ $? -eq 1 ]; then
		return 1
	fi

	port=$(whiptail --inputbox "TCP server port" 20 60 "$port" 3>&1 1>&2 2>&3)
	if [ $? -eq 1 ]; then
		return 1
	fi

	stationid=$(whiptail --inputbox "StationID to set in AIS messages" 20 60 "$stationid" 3>&1 1>&2 2>&3)
	if [ $? -eq 1 ]; then
		return 1
	fi

	msgspersec=$(whiptail --inputbox "AIS messages / second upper limit" 20 60 "$msgspersec" 3>&1 1>&2 2>&3)
	if [ $? -eq 1 ]; then
		return 1
	fi

	msgspersecpermmsi=$(whiptail --inputbox "AIS messages / second / mmsi upper limit" 20 60 "$msgspersecpermmsi" 3>&1 1>&2 2>&3)
	if [ $? -eq 1 ]; then
		return 1
	fi

	# TODO: Validate IP and port

	cat > /tmp/elcheapoais-config <<EOF
server="$server"
port="$port"
stationid="$stationid"
msgspersec="$msgspersec"
msgspersecpermmsi="$msgspersecpermmsi"
EOF
	
        sudo mkdir -p /etc/elcheapoais
	sudo mkdir -p /var/log/elcheapoais

	sudo mv /tmp/elcheapoais-config /etc/elcheapoais/config
	sudo cp elcheapo-calibrate.sh /usr/local/bin/elcheapo-calibrate.sh
	sudo cp elcheapoais-receiver.sh /usr/local/bin/elcheapoais-receiver.sh
	sudo cp elcheapoais-downsampler.sh /usr/local/bin/elcheapoais-downsampler.sh
	chmod a+x /usr/local/bin/elcheapo-calibrate.sh /usr/local/bin/elcheapoais-receiver.sh /usr/local/bin/elcheapoais-downsampler.sh

	sudo cp elcheapoais-receiver.service /lib/systemd/system/elcheapoais-receiver.service
	sudo cp elcheapoais-downsampler.service /lib/systemd/system/elcheapoais-downsampler.service
	sudo chmod 644 /lib/systemd/system/elcheapoais-receiver.service /lib/systemd/system/elcheapoais-downsampler.service

	sudo systemctl daemon-reload
	sudo systemctl enable elcheapoais-receiver.service
	sudo systemctl enable elcheapoais-downsampler.service

	ASK_TO_REBOOT=1
	whiptail --msgbox "\
Setup done. To start service reboot or execute:
sudo systemctl start elcheapoais-receiver.service
sudo systemctl start elcheapoais-downsampler.service

Check logs here:
/var/log/elcheapoais/
" 20 70 1

	return 0
}

do_test_run() {
        source <(./elcheapo-calibrate.sh)
    
	whiptail --yesno "The program is going to execute rtl_ais now so you can check if you are able to receive NMEA sentences to the console.\n\nThe average absolute error $PPM ppm.\n(If that value is incorrect, cancel and run the calibration again)" 20 60 2 \
		--yes-button Cancel --no-button Run
	RET=$?
	if [ $RET -eq 1 ]; then
		sudo rtl_ais -n -p $PPM -g 60 -S 60
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
