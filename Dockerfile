#
# Basic Parameters
#
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.14.5-10"
ARG PKG="samba"
ARG ROCKY_VERSION="8.5"
ARG SRC_IMAGE_BASE="345280441424.dkr.ecr.ap-south-1.amazonaws.com"
ARG SRC_IMAGE_REPO="ark_samba_rpmbuild"
ARG SRC_IMAGE="${SRC_IMAGE_BASE}/${SRC_IMAGE_REPO}:${VER}"

FROM "${SRC_IMAGE}" as src

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
		python3-pyyaml \
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
		which \
    && \
    yum -y clean all && \
    update-alternatives --set python /usr/bin/python3
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

EXPOSE 80
EXPOSE 636

#
# Set up script and run
#
ADD init.sh /init.sh
ADD export-cafile /usr/local/bin/export-cafile
ADD test-ready.sh /test-ready.sh
ADD test-live.sh /test-live.sh
COPY samba-directory-templates.tar.gz /
RUN chmod 755 /init.sh /usr/local/bin/export-cafile
ENTRYPOINT /init.sh
