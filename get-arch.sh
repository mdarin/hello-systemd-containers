#!/usr/bin/sh

#  TODO

arch="$(apk --print-arch)"; \
	url=; \
	case "$arch" in \
		'x86_64') \
			url='https://dl.google.com/go/go1.25.1.linux-amd64.tar.gz'; \
			sha256='7716a0d940a0f6ae8e1f3b3f4f36299dc53e31b16840dbd171254312c41ca12e'; \
			;; \
		'armhf') \
			url='https://dl.google.com/go/go1.25.1.linux-armv6l.tar.gz'; \
			sha256='eb949be683e82a99e9861dafd7057e31ea40b161eae6c4cd18fdc0e8c4ae6225'; \
			;; \
		'armv7') \
			url='https://dl.google.com/go/go1.25.1.linux-armv6l.tar.gz'; \
			sha256='eb949be683e82a99e9861dafd7057e31ea40b161eae6c4cd18fdc0e8c4ae6225'; \
			;; \
		'aarch64') \
			url='https://dl.google.com/go/go1.25.1.linux-arm64.tar.gz'; \
			sha256='65a3e34fb2126f55b34e1edfc709121660e1be2dee6bdf405fc399a63a95a87d'; \
			;; \
		'x86') \
			url='https://dl.google.com/go/go1.25.1.linux-386.tar.gz'; \
			sha256='d03cdcbc9bd8baf5cf028de390478e9e2b3e4d0afe5a6582dedc19bfe6a263b2'; \
			;; \
		'ppc64le') \
			url='https://dl.google.com/go/go1.25.1.linux-ppc64le.tar.gz'; \
			sha256='8b0c8d3ee5b1b5c28b6bd63dc4438792012e01d03b4bf7a61d985c87edab7d1f'; \
			;; \
		'riscv64') \
			url='https://dl.google.com/go/go1.25.1.linux-riscv64.tar.gz'; \
			sha256='22fe934a9d0c9c57275716c55b92d46ebd887cec3177c9140705efa9f84ba1e2'; \
			;; \
		's390x') \
			url='https://dl.google.com/go/go1.25.1.linux-s390x.tar.gz'; \
			sha256='9cfe517ba423f59f3738ca5c3d907c103253cffbbcc2987142f79c5de8c1bf93'; \
			;; \
		*) echo >&2 "error: unsupported architecture '$arch' (likely packaging update needed)"; exit 1 ;; \
	esac;
