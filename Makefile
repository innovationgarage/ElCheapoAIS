all: kalibrate-rtl rtl-ais

kalibrate-rtl:
	git clone https://github.com/steve-m/kalibrate-rtl
	cd kalibrate-rtl; ./bootstrap && CXXFLAGS='-W -Wall -O3'
	cd kalibrate-rtl; ./configure --prefix /usr
	cd kalibrate-rtl; make

rtl-ais:
	git clone https://github.com/dgiardini/rtl-ais
	cd rtl-ais; make

install: install-kalibrate-rtl install-rtl-ais install-elcheapoais

install-kalibrate-rtl: kalibrate-rtl
	cd kalibrate-rtl; make DESTDIR=$(DESTDIR) install

install-rtl-ais: rtl-ais
	mkdir -p $(DESTDIR)/usr/bin/
	cd rtl-ais; cp rtl_ais $(DESTDIR)/usr/bin/


install-elcheapoais:
	mkdir -p $(DESTDIR)/usr/bin
	mkdir -p $(DESTDIR)/lib/systemd/system
	mkdir -p $(DESTDIR)/etc/elcheapoais
	mkdir -p $(DESTDIR)/var/log/elcheapoais

	cp 2_rpi/installer/config $(DESTDIR)/etc/elcheapoais/config

	cp 2_rpi/installer/elcheapo-calibrate.sh $(DESTDIR)/usr/bin/elcheapo-calibrate.sh
	cp 2_rpi/installer/elcheapoais.sh $(DESTDIR)/usr/bin/elcheapoais.sh
	chmod a+x $(DESTDIR)/usr/bin/elcheapo-calibrate.sh $(DESTDIR)/usr/bin/elcheapoais.sh

	cp 2_rpi/installer/elcheapoais.service $(DESTDIR)/lib/systemd/system/elcheapoais.service
	chmod 644 $(DESTDIR)/lib/systemd/system/elcheapoais.service
