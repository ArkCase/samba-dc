#
# Basic Parameters
#
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.14.5-10"
ARG PKG="samba"
ARG ROCKY_VERSION="8.5"

#
# To build the RPMs
#
FROM rockylinux:${ROCKY_VERSION} as src

#
# Basic Parameters
#
ARG ARCH
ARG OS
ARG VER
ARG PKG
ARG ROCKY_VERSION

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
# Download the requisite SRPMs
#
WORKDIR /root/rpmbuild
RUN yum -y install wget
# First try the main repository
ENV REPO="https://dl.rockylinux.org/pub/rocky/${ROCKY_VERSION}/BaseOS/source/tree/Packages"
RUN wget --recursive --level 2 --no-parent --no-directories "${REPO}" --directory-prefix=. --accept "samba-*.src.rpm" --accept "libldb-*.src.rpm" || true
# Now try the vault repository
ENV REPO="https://dl.rockylinux.org/vault/rocky/${ROCKY_VERSION}/BaseOS/source/tree/Packages"
RUN wget --recursive --level 2 --no-parent --no-directories "${REPO}" --directory-prefix=. --accept "samba-*.src.rpm" --accept "libldb-*.src.rpm" || true
ENV REPO=""
COPY find-latest-srpm .
COPY get-dist .

#
# We have the RPMs available, now find the latest ones and build them
#

#
# Build the one missing build dependency - python3-ldb-devel
#
RUN LIBLDB_SRPM="$( ./find-latest-srpm libldb-*.src.rpm )" && \
    if [ -z "${LIBLDB_SRPM}" ] ; then echo "No libldb SRPM was found" ; exit 1 ; fi && \
    yum-builddep -y "${LIBLDB_SRPM}" && \
    rpmbuild --clean --rebuild "${LIBLDB_SRPM}"

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
RUN SAMBA_SRPM="$( ./find-latest-srpm samba-*.src.rpm )" && \
    if [ -z "${SAMBA_SRPM}" ] ; then echo "No Samba SRPM was found" ; exit 1 ; fi && \
    yum-builddep -y "${SAMBA_SRPM}" && \
    yum -y install \
		bind \
		krb5-server \
		ldb-tools \
		python3-cryptography \
		python3-iso8601 \
		python3-markdown \
		python3-pyasn1 \
		python3-setproctitle \
		tdb-tools && \
    DIST="$( ./get-dist "${SAMBA_SRPM}" )" && \
    if [ -z "${DIST}" ] ; then echo "Failed to identify the distribution for the SRPM [${SAMBA_SRPM}]" ; exit 1 ; fi && \
    rpmbuild --clean --define "dist .${DIST}" --define "${DIST} 1" --with dc --rebuild "${SAMBA_SRPM}"
RUN rm -rf RPMS/repodata
RUN createrepo RPMS

#
# Deploy the artifacts
#

# RUN curl -v --user "${NEXUS_AUTH}" --upload-file ./test.rpm "${NEXUS_URL}/repository/${NEXUS_REPO}/..."

#
# For actual execution
#
FROM rockylinux:${ROCKY_VERSION}

#
# Basic Parameters
#
ARG ARCH
ARG OS
ARG VER
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
