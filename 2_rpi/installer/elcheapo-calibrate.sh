#! /bin/bash

PROD="$(rtl_eeprom 2>&1 | grep "Product:" | sed -e "s+.*:[ \t]*++g")"
SERIAL="$(rtl_eeprom 2>&1 | grep "Serial number:" | sed -e "s+.*:[ \t]*++g")"

if [ "${PROD::1}" != "K" ]; then
    {
	echo "Uncalibrated device found. Calibrating (this will take half an hour or so)... "

	kal -g 42 -e 22 -s 850 2>&1 | tee stations.txt
	chan="$(cat stations.txt | sed -n 's/.*chan: \(.*\) (.*power: \(.*\)/\2 \1/p' | sort | tail -n 1 | {
	    read a b
	    echo $b
	})"
	echo "Using channel $chan"
	kal -e 41 -c $chan -v | tee calibration.txt
	cat calibration.txt | sed -n "s/average absolute error: \(.*\) ppm/\1/p" >ppm_error.txt

	# Write calibrated PPM error and a random serial number to the EEPROM
	PPM="$(cat ppm_error.txt)"
	PROD="$(python -c "import base64, struct; print 'K' + base64.b64encode(struct.pack('<d', $PPM))")"
	SERIAL="$(python -c "import base64, struct, random; print base64.b64encode(struct.pack('<9B', *(random.getrandbits(8) for _ in xrange(9))))")"

	echo y | rtl_eeprom -p "$PROD" -s "$SERIAL"
    } >&2
fi

PPM="$(python -c "import base64, struct; print struct.unpack('<d', base64.b64decode('$PROD'[1:]))[0]")"

cat <<EOF
PPM="$PPM"
SERIAL="$SERIAL"
EOF
