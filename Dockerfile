#
# Basic Parameters
#
ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG BASE_REPO="rockylinux"
ARG BASE_TAG="8.5"
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.14.5-10"
ARG PKG="samba"
ARG SRC_BASE_REGISTRY="${PUBLIC_REGISTRY}"
ARG SRC_BASE_REPO="arkcase/samba-rpmbuild"
ARG STEP_VER="0.23.3"
ARG STEP_SRC="https://dl.step.sm/gh-release/cli/gh-release-header/v${STEP_VER}/step-cli_${STEP_VER}_amd64.rpm"

FROM "${SRC_BASE_REGISTRY}/${SRC_BASE_REPO}:${VER}" as src

#
# For actual execution
#
# FROM "${PUBLIC_REGISTRY}/${BASE_REPO}:${BASE_TAG}"
FROM "${BASE_REPO}:${BASE_TAG}"

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
RUN yum -y install \
        epel-release \
        yum-utils \
    && \
    yum -y update && \
    yum-config-manager --setopt=*.priority=50 --save
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
        openvpn \
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
    update-alternatives --set python /usr/bin/python3 && \
    rm -rf /rpm /etc/yum.repos.d/arkcase.repo

#
# Declare some important volumes
#
VOLUME /config
VOLUME /vpn
VOLUME /var/log/samba
VOLUME /var/lib/samba

EXPOSE 389
EXPOSE 636

#
# Set up script and run
#
COPY entrypoint test-ready.sh test-live.sh samba-directory-templates.tar.gz /
RUN chmod 755 /entrypoint
ENTRYPOINT /entrypoint
