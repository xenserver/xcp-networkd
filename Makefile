BINDIR ?= /usr/bin
SBINDIR ?= /usr/sbin
ETCDIR ?= /etc
MANDIR ?= /usr/share/man/man1
all: build doc

.PHONY: test install uninstall clean

export OCAMLRUNPARAM=b
J=4

setup.bin: setup.ml
	@ocamlopt.opt -o $@ $< || ocamlopt -o $@ $< || ocamlc -o $@ $<
	@rm -f setup.cmx setup.cmi setup.o setup.cmo

setup.data: setup.bin
	@./setup.bin -configure --enable-tests

build: setup.data setup.bin networkd/version.ml
	@./setup.bin -build -j $(J)
	mv networkd.native xcp-networkd
	./xcp-networkd --help=groff > xcp-networkd.1

networkd/version.ml: VERSION
	echo "let version = \"$(shell cat VERSION)\"" > networkd/version.ml

doc: setup.data setup.bin
	@./setup.bin -doc -j $(J)

test: setup.bin build
	@./setup.bin -test

install:
	mkdir -p $(DESTDIR)$(SBINDIR)
	install xcp-networkd $(DESTDIR)$(SBINDIR)/xcp-networkd
	mkdir -p $(DESTDIR)$(MANDIR)
	install xcp-networkd.1 $(DESTDIR)$(MANDIR)/xcp-networkd.1
	mkdir -p $(DESTDIR)$(BINDIR)
	install networkd_db.native $(DESTDIR)$(BINDIR)/networkd_db

uninstall:
	rm -f $(DESTDIR)$(SBINDIR)/xcp-networkd
	rm -f $(DESTDIR)$(MANDIR)/xcp-networkd.1
	rm -f $(DESTDIR)$(SBINDIR)/networkd_db

clean:
	@ocamlbuild -clean
	@rm -f setup.data setup.log setup.bin
	rm networkd/version.ml
	rm xcp-networkd.1


# make coverage 
# prepares for building with coverage analysis
#
# make uncover
# reverses the setup from "make coverage"

coverage: _tags _tags.coverage 
	test ! -f _tags.orig && mv _tags _tags.orig || true
	cat _tags.coverage _tags.orig > _tags

uncover: _tags.orig
	mv _tags.orig _tags

.PHONY: default coverage uncover
	
