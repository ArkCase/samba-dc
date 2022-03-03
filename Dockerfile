#
# To build the RPMs
#
FROM rockylinux:8.5 as src

#
# Basic Parameters
#
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.14.5-9"
ARG DIST="el8_5"
ARG LDB_VER="2.3.0-2"
ARG LDB_DIST="el8"
ARG PKG="samba"
ARG SRC="https://dl.rockylinux.org/pub/rocky/8/BaseOS/source/tree/Packages/s/samba-${VER}.${DIST}.src.rpm"

#
# Some important labels
#
LABEL ORG="Armedia LLC"
LABEL MAINTAINER="Armedia Devops Team <devops@armedia.com>"
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
# Build the one missing build dependency - python3-ldb-devel
#
RUN curl -O "https://dl.rockylinux.org/pub/rocky/8/BaseOS/source/tree/Packages/l/libldb-${LDB_VER}.${LDB_DIST}.src.rpm"
RUN yum-builddep -y "libldb-${LDB_VER}.${LDB_DIST}.src.rpm"
RUN rpmbuild --clean --rebuild "libldb-${LDB_VER}.${LDB_DIST}.src.rpm"

#
# Create a repository that facilitates installation later
#
WORKDIR /root/rpmbuild
RUN yum -y install createrepo
RUN createrepo RPMS
COPY armedia.repo /etc/yum.repos.d
RUN ln -svf $(readlink -f RPMS) /rpm

RUN yum -y install python3-ldb python3-ldb-devel

#
# Build Samba now
#
WORKDIR /root/rpmbuild
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
FROM rockylinux:8.5

#
# Basic Parameters
#
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.14.5-9"
ARG DIST="el8_5"
ARG LDB_VER="2.3.0-2"
ARG PKG="samba"

#
# Some important labels
#
LABEL ORG="Armedia LLC"
LABEL MAINTAINER="Armedia Devops Team <devops@armedia.com>"
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
COPY armedia.repo /etc/yum.repos.d
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
RUN rm -rf /rpm /etc/yum.repos.d/armedia.repo


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
RUN chmod 755 /init.sh
ENTRYPOINT /init.sh
