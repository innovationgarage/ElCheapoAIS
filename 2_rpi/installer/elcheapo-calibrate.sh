#! /bin/bash

argparse() {
   export ARGS=()
   for _ARG in "$@"; do
       if [ "${_ARG##--*}" == "" ]; then
           _ARG="${_ARG#--}"
           if [ "${_ARG%%*=*}" == "" ]; then
               _ARGNAME="${_ARG%=*}"
               _ARGVALUE="${_ARG#*=}"
           else
               _ARGNAME="${_ARG}"
               _ARGVALUE="True"
           fi
           _ARGNAME="$(echo ${_ARG%=*} | tr - _)"
           eval "export ARG_${_ARGNAME}"='"${_ARGVALUE}"'
       else
           ARGS+=($_ARG)
       fi
   done
}

argparse "$@"

if [ "$ARG_help" ]; then
    cat <<EOF
Calibrate an RTL2838 SDR USB stick and stores the calibration offset in
EEPROM on the stick.

If called without arguments, the first available device is queried for
calibration parameters and they are returned. If the device is
uncalibrated, it is first calibrated, the parameters stored in EEPROM
and then returned.

Usage: elcheapo-calibrate.sh OPTIONS

Options:

    --help Show this help
    --device=index Use specificed device. Default 0.
    --recalibrate Force recalibration, even if the device is already
      calibrated
    --no-calibration Don't calibrate if not already calibrated, return
      immediately with no output.

Output (On stdout):

    PPM=frequency_offset
    SERIAL=unique_serial_string
EOF
    exit 1
fi

RTL_EEPROM=rtl_eeprom
KAL=kal
if [ "$ARG_device" ]; then
    echo "Using device ${ARG_device}." >&2
    RTL_EEPROM="rtl_eeprom -d $ARG_device"
    KAL="kal -d $ARG_device"
fi

if ! $RTL_EEPROM 2>&1 | grep "Serial number:" > /dev/null; then
    $RTL_EEPROM
    exit 1
fi


PROD="$($RTL_EEPROM 2>&1 | grep "Product:" | sed -e "s+.*:[ \t]*++g")"
SERIAL="$($RTL_EEPROM 2>&1 | grep "Serial number:" | sed -e "s+.*:[ \t]*++g")"

if [ "${PROD::1}" != "K" ] || [ "$ARG_recalibrate" ]; then
    {
        if [ "$ARG_no_calibration" ]; then
            echo "Uncalibrated device found." >&2
            exit 1;
        fi
        
	echo "Uncalibrated device found. Calibrating (this will take half an hour or so)... "

	$KAL -g 42 -e 22 -s 850 2>&1 | tee stations.txt
	chan="$(cat stations.txt | sed -n 's/.*chan: \(.*\) (.*power: \(.*\)/\2 \1/p' | sort | tail -n 1 | {
	    read a b
	    echo $b
	})"
	echo "Using channel $chan"
	$KAL -e 41 -c $chan -v | tee calibration.txt
	cat calibration.txt | sed -n "s/average absolute error: \(.*\) ppm/\1/p" >ppm_error.txt

	# Write calibrated PPM error and a random serial number to the EEPROM
	PPM="$(cat ppm_error.txt)"
	PROD="$(python -c "import base64, struct; print 'K' + base64.b64encode(struct.pack('<d', $PPM))")"
	SERIAL="$(python -c "import base64, struct, random; print base64.b64encode(struct.pack('<9B', *(random.getrandbits(8) for _ in xrange(9))))")"

	echo y | $RTL_EEPROM -p "$PROD" -s "$SERIAL"
    } >&2
fi

PPM="$(python -c "import base64, struct; print struct.unpack('<d', base64.b64decode('$PROD'[1:]))[0]")"

cat <<EOF
PPM="$PPM"
SERIAL="$SERIAL"
EOF
