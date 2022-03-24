FROM alpine:3.15.2 as build_rootfs
ARG REL=focal
ARG ARCH=amd64

# install packages
RUN apk add --no-cache \
        bash \
        curl \
        tzdata \
        xz

# grab base tarball
RUN mkdir /root-out && \
	curl -o /rootfs.tar.gz -L "https://partner-images.canonical.com/core/${REL}/current/ubuntu-${REL}-core-cloudimg-${ARCH}-root.tar.gz" && \
	tar xf /rootfs.tar.gz -C /root-out

# Runtime stage
FROM scratch
COPY --from=build_rootfs /root-out/ /

ARG BUILD_DATE="${BUILD_DATE:-date +%D}"
ARG VERSION

LABEL \
	build_date=$BUILD_DATE \
	version=$VERSION \
	maintainer="jessenich <https://github.com/jessenich>" \
	org.opencontainers.image.source="https://github.com/jessenich/docker-baseimage-ubuntu"

# set version for s6 overlay
ARG OVERLAY_VERSION="v2.2.0.3"
ARG OVERLAY_ARCH="amd64"

# add s6 overlay
ADD "https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}-installer" /tmp/
RUN chmod +x "/tmp/s6-overlay-${OVERLAY_ARCH}-installer" && "/tmp/s6-overlay-${OVERLAY_ARCH}-installer" / && rm "/tmp/s6-overlay-${OVERLAY_ARCH}-installer"

# set environment variables
ARG DEBIAN_FRONTEND="noninteractive"

ENV HOME="/root" \
	LANGUAGE="en_US.UTF-8" \
	LANG="en_US.UTF-8" \
	TERM="xterm"

COPY rootfs/ /

RUN set -xe && \
	echo 'deb http://archive.ubuntu.com/ubuntu/ focal main restricted' > /etc/apt/sources.list && \
	echo 'deb http://archive.ubuntu.com/ubuntu/ focal-updates main restricted' >> /etc/apt/sources.list && \
	echo 'deb http://archive.ubuntu.com/ubuntu/ focal universe multiverse' >> /etc/apt/sources.list && \
	echo 'deb http://archive.ubuntu.com/ubuntu/ focal-updates universe multiverse' >> /etc/apt/sources.list && \
	echo 'deb http://archive.ubuntu.com/ubuntu/ focal-security main restricted' >> /etc/apt/sources.list && \
	echo 'deb http://archive.ubuntu.com/ubuntu/ focal-security universe multiverse' >> /etc/apt/sources.list && \
	echo '#!/bin/sh' > /usr/sbin/policy-rc.d && \
	echo 'exit 101' >> /usr/sbin/policy-rc.d && \
	chmod +x /usr/sbin/policy-rc.d && \
	dpkg-divert --local --rename --add /sbin/initctl && \
	cp -a /usr/sbin/policy-rc.d /sbin/initctl && \
	sed -i 's/^exit.*/exit 0/' /sbin/initctl && \
	echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
	echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > /etc/apt/apt.conf.d/docker-clean && \
	echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> /etc/apt/apt.conf.d/docker-clean && \
	echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> /etc/apt/apt.conf.d/docker-clean && \
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/docker-no-languages && \
	echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/docker-gzip-indexes && \
	echo 'Apt::AutoRemove::SuggestsImportant "false";' > /etc/apt/apt.conf.d/docker-autoremove-suggests && \
	mkdir -p /run/systemd && \
	echo 'docker' > /run/systemd/container && \
	apt-get update && \
	apt-get install -y \
		apt-utils \
		locales && \
	apt-get install -y \
		curl \
		gnupg \
		patch \
		tzdata \
		zsh && \
	locale-gen en_US.UTF-8 && \
	useradd -u 1000 -U -s "$(command -v zsh)" jessenich && \
	usermod -G users jessenich && \
	chsh --shell "$(command -v zsh)" && \
	mkdir -p /app /config /defaults && \
	mv /usr/bin/with-contenv /usr/bin/with-contenvb && \
	patch -u /etc/s6/init/init-stage2.patch -i /tmp/patch/etc/s6/init/init-stage2.patch && \
	apt-get remove -y patch && \
	apt-get autoremove && \
	apt-get clean && \
	rm -rf /tmp/* \
		/var/lib/apt/lists/* \
		/var/tmp/*

ENTRYPOINT ["/init"]
