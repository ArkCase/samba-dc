#
# Basic Parameters
#
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.15.5-10"
ARG DIST="el8_6"
ARG PKG="samba"

#
# To build the RPMs
#
FROM rockylinux:8.6 as src

#
# Basic Parameters
#
ARG ARCH
ARG OS
ARG VER
ARG DIST
ARG PKG
# ARG ROCKY_REPO="https://dl.rockylinux.org/pub/rocky/8/BaseOS/source/tree/Packages"
ARG ROCKY_REPO="https://dl.rockylinux.org/vault/rocky/8.6/BaseOS/source/tree/Packages"
ARG SRC="${ROCKY_REPO}/s/samba-${VER}.${DIST}.src.rpm"

#
# Some important labels
#
LABEL ORG="ArkCase LLC"
LABEL MAINTAINER="ArkCase Support <support@arkcase.com>"
LABEL APP="Samba"
LABEL VERSION="${VER}"

#
# Full update
#
RUN yum -y install epel-release
RUN yum -y update
RUN yum -y install yum-utils rpm-build which

#
# Enable the required repositories
#
RUN yum-config-manager \
		--enable devel \
		--enable powertools

#
# Download the SRPMs
#
WORKDIR /root/rpmbuild
COPY find-latest-srpm .
RUN wget --recursive --level 2 --no-parent --no-directories "${ROCKY_REPO}" --directory-prefix=. --accept "samba-*.src.rpm" --accept "libldb-*.src.rpm"

#
# This will have downloaded all available libldb and samba source RPMs, so now we endeavor to discover the versions at play
#

#
# Build the one missing build dependency - python3-ldb-devel
#
RUN LIBLDB_SRPM="$( \
	find . -type f -name 'libldb-*.src.rpm' | \
	)"
RUN yum-builddep -y "${LIBLDB_SRPM}"
RUN rpmbuild --clean --rebuild "${LIBLDB_SRPM}"

#
# Create a repository that facilitates installation later
#
RUN yum -y install createrepo
RUN createrepo RPMS
COPY arkcase.repo /etc/yum.repos.d
RUN ln -svf $(readlink -f RPMS) /rpm

RUN yum -y install python3-ldb python3-ldb-devel

#
# Build Samba now
#
RUN curl -O "${SRC}"
RUN yum-builddep -y "samba-${VER}.${DIST}.src.rpm"
RUN yum -y install \
		bind \
		krb5-server \
		ldb-tools \
		python3-iso8601 \
		python3-markdown \
		python3-pyasn1 \
		python3-setproctitle \
		tdb-tools
RUN rpmbuild --clean --define "dist .${DIST}" --define "${DIST} 1" --with dc --rebuild "samba-${VER}.${DIST}.src.rpm"
RUN rm -rf RPMS/repodata
RUN createrepo RPMS

#
# For actual execution
#
FROM rockylinux:8.6

#
# Basic Parameters
#
ARG ARCH
ARG OS
ARG VER
ARG DIST
ARG PKG

#
# Some important labels
#
LABEL ORG="ArkCase LLC"
LABEL MAINTAINER="ArkCase Support <support@arkcase.com>"
LABEL APP="Samba"
LABEL VERSION="${VER}"

#
# Install all apps
# The third line is for multi-site config (ping is for testing later)
#
RUN yum -y install epel-release yum-utils
RUN yum -y update
RUN yum-config-manager --setopt=*.priority=50 --save
COPY --from=src /root/rpmbuild/RPMS /rpm
COPY arkcase.repo /etc/yum.repos.d
RUN yum -y install \
		attr \
		bind-utils \
		findutils \
		krb5-pkinit \
		krb5-server \
		krb5-workstation \
		nc \
		net-tools \
		openldap-clients \
		python3-samba \
		python3-samba-dc \
		samba \
		samba-dc \
		samba-dc-bind-dlz \
		samba-krb5-printing \
		samba-vfs-iouring \
		samba-winbind \
		samba-winbind-krb5-locator \
		samba-winexe \
		sssd-krb5 \
		supervisor \
		telnet \
		which
RUN rm -rf /rpm /etc/yum.repos.d/arkcase.repo


#
# This is for multisite (really?)
#
RUN yum -y install openvpn

#
# Declare some important volumes
#
VOLUME /config
VOLUME /vpn
VOLUME /var/log/samba
VOLUME /var/lib/samba

#
# Set up script and run
#
ADD init.sh /init.sh
ADD test-ready.sh /test-ready.sh
ADD test-live.sh /test-live.sh
COPY samba-directory-templates.tar.gz /
RUN chmod 755 /init.sh
ENTRYPOINT /init.sh
