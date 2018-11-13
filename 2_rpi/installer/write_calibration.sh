#! /bin/bash

PPM="$(cat ppm_error.txt)"

PROD="$(python -c "import base64, struct; print 'K' + base64.b64encode(struct.pack('<d', $PPM))")"
SERIAL="$(python -c "import base64, struct, random; print base64.b64encode(struct.pack('<9B', *(random.getrandbits(8) for _ in xrange(9))))")"

echo y | rtl_eeprom -p "$PROD" -s "$SERIAL"
