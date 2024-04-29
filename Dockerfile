#
# Basic Parameters
#
ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.14.5"
ARG PKG="samba"

ARG STEP_VER="0.26.1"
ARG STEP_SRC="https://dl.step.sm/gh-release/cli/gh-release-header/v${STEP_VER}/step-cli_${STEP_VER}_amd64.rpm"

ARG SAMBA_REGISTRY="${PUBLIC_REGISTRY}"
ARG SAMBA_REPO="arkcase/samba-rpmbuild"
ARG SAMBA_IMG="${SAMBA_REGISTRY}/${SAMBA_REPO}:${VER}"

ARG BASE_REPO="rockylinux"
ARG BASE_VER="8.5"
ARG BASE_IMG="${BASE_REPO}:${BASE_VER}"

FROM "${SAMBA_IMG}" as src

#
# For actual execution
#
# FROM "${PUBLIC_REGISTRY}/${BASE_REPO}:${BASE_VER}"
FROM "${BASE_IMG}"

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
        openssl \
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
        "${STEP_SRC}" \
    && \
    yum -y clean all && \
    update-alternatives --set python /usr/bin/python3 && \
    rm -rf /rpm /etc/yum.repos.d/arkcase.repo

#
# Declare some important volumes
#
VOLUME /app/conf
VOLUME /app/init
VOLUME /vpn
VOLUME /var/log/samba
VOLUME /var/lib/samba

EXPOSE 389
EXPOSE 636

#
# Set up script and run
#
COPY --chown=root:root entrypoint test-ready.sh test-live.sh test-startup.sh samba-directory-templates.tar.gz /
COPY --chown=root:root acme-init acme-validate /usr/local/bin/
RUN chmod 755 /entrypoint /test-ready.sh /test-live.sh /test-startup.sh /usr/local/bin/acme-init /usr/local/bin/acme-validate

# This is required by acme-init. It's ok to set it to root for this container
ENV ACM_GROUP="root"

HEALTHCHECK CMD /test-ready.sh

ENTRYPOINT /entrypoint
