#! /bin/bash

PROD="$(lsusb -d 0bda:2838 -v | grep iProduct | sed -e "s+  *[^ ]*  *[^ ]*  *++g")"
SERIAL="$(lsusb -d 0bda:2838 -v | grep iSerial | sed -e "s+  *[^ ]*  *[^ ]*  *++g")"

if [ ${PROD::1} != "K" ]; then
    echo "NOT CALIBRATED"
    exit 1
fi

PPM="$(python -c "import base64, struct; print struct.unpack('<d', base64.b64decode('$PROD'[1:]))[0]")"

echo "$PPM $SERIAL"
