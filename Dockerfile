#
# Basic Parameters
#
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.14.5-10"
ARG PKG="samba"
ARG BASE_REGISTRY
ARG BASE_REPO="rockylinux"
ARG BASE_TAG="8.5"
ARG SRC_BASE_REGISTRY="${BASE_REGISTRY}"
ARG SRC_BASE_REPO="arkcase/samba-rpmbuild"
ARG SRC_IMAGE="${SRC_BASE_REGISTRY}/${SRC_BASE_REPO}:${VER}"
ARG STEP_VER="0.23.3"
ARG STEP_SRC="https://dl.step.sm/gh-release/cli/gh-release-header/v${STEP_VER}/step-cli_${STEP_VER}_amd64.rpm"

FROM "${SRC_IMAGE}" as src

#
# For actual execution
#
# FROM "${BASE_REGISTRY}/${BASE_REPO}:${BASE_TAG}
FROM "${BASE_REPO}:${BASE_TAG}

#
# Basic Parameters
#
ARG ARCH
ARG OS
ARG VER
ARG PKG
ARG STEP_VER
ARG STEP_SRC

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
    curl -L -o step.rpm "${STEP_SRC}" && \
    yum -y install step.rpm && \
    rm -rf step.rpm && \
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
ADD test-ready.sh /test-ready.sh
ADD test-live.sh /test-live.sh
COPY samba-directory-templates.tar.gz /
RUN chmod 755 /init.sh
ENTRYPOINT /init.sh
