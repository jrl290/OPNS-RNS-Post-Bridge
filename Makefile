# OPNS-RNS-Post-Bridge Makefile
#
# Build and package rnsd as an OPNSense plugin for FreeBSD/amd64.

PROJECT    := opns-rns-post-bridge
VERSION    := $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.1.0")
RNSD_SRC   := ../Reticulum-rust
PKG_DIR    := pkg
OUTPUT     := $(PKG_DIR)/$(PROJECT)-$(VERSION).txz

.PHONY: all rnsd package clean install help

all: rnsd package

## Build rnsd binary for FreeBSD/amd64 using cross-rs
rnsd: $(PKG_DIR)/files/usr/local/bin/rnsd

$(PKG_DIR)/files/usr/local/bin/rnsd: $(RNSD_SRC)/Cargo.toml $(shell find $(RNSD_SRC)/src -name '*.rs')
	@echo "=== Building rnsd for FreeBSD/amd64 ==="
	cd $(RNSD_SRC) && \
		cross build --release --target x86_64-unknown-freebsd \
			--no-default-features \
			-p reticulum_rust
	cp $(RNSD_SRC)/target/x86_64-unknown-freebsd/release/rnsd $@
	@echo "=== rnsd binary ready: $@ ==="

## Build without cross-rs (requires freebsd target installed via rustup)
rnsd-local: $(PKG_DIR)/files/usr/local/bin/rnsd

rnsd-local:
	cd $(RNSD_SRC) && \
		cargo build --release --target x86_64-unknown-freebsd \
			--no-default-features \
			-p reticulum_rust
	cp $(RNSD_SRC)/target/x86_64-unknown-freebsd/release/rnsd $(PKG_DIR)/files/usr/local/bin/rnsd

## Package into a FreeBSD .txz
package: rnsd $(OUTPUT)

$(OUTPUT): $(PKG_DIR)/+MANIFEST $(PKG_DIR)/+POST_INSTALL $(PKG_DIR)/+PRE_DEINSTALL $(PKG_DIR)/files/usr/local/bin/rnsd
	@echo "=== Creating OPNSense package ==="
	@# Generate +MANIFEST with correct version
	sed "s/__VERSION__/$(VERSION)/g" $(PKG_DIR)/+MANIFEST.in > $(PKG_DIR)/+MANIFEST
	@# Build the .txz
	cd $(PKG_DIR) && \
		tar cvf - +MANIFEST +POST_INSTALL +PRE_DEINSTALL files | \
		xz -9 > ../$(OUTPUT).tmp && \
		mv ../$(OUTPUT).tmp ../$(OUTPUT)
	@echo "=== Package created: $(OUTPUT) ==="

## Install to a remote OPNSense box
install: $(OUTPUT)
	@test -n "$(OPNSENSE_HOST)" || (echo "ERROR: set OPNSENSE_HOST"; exit 1)
	scp $(OUTPUT) root@$(OPNSENSE_HOST):/tmp/
	ssh root@$(OPNSENSE_HOST) 'pkg install -y /tmp/$(PROJECT)-$(VERSION).txz && rm /tmp/$(PROJECT)-$(VERSION).txz'

## Clean build artifacts
clean:
	rm -f $(PKG_DIR)/files/usr/local/bin/rnsd
	rm -f $(OUTPUT)
	rm -f $(PKG_DIR)/+MANIFEST

## Show help
help:
	@grep '^##' Makefile | sed 's/^## //'
