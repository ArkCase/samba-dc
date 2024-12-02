#
# Basic Parameters
#
ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.19.4"
ARG PKG="samba"

ARG BASE_REGISTRY="${PUBLIC_REGISTRY}"
ARG BASE_REPO="arkcase/base"
ARG BASE_VER="8"
ARG BASE_VER_PFX=""
ARG BASE_IMG="${BASE_REGISTRY}/${BASE_REPO}:${BASE_VER_PFX}${BASE_VER}"

ARG SAMBA_REGISTRY="${BASE_REGISTRY}"
ARG SAMBA_RPM_REPO="arkcase/samba-rpmbuild"
ARG SAMBA_VER_PFX="${BASE_VER_PFX}"
ARG SAMBA_IMG="${SAMBA_REGISTRY}/${SAMBA_RPM_REPO}:${SAMBA_VER_PFX}${VER}"

FROM "${SAMBA_IMG}" AS src

ARG BASE_IMG

FROM "${BASE_IMG}"

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
RUN yum -y install \
        epel-release \
        yum-utils \
    && \
    yum -y update && \
    yum-config-manager --setopt=*.priority=50 --save
COPY --from=src /rpm /rpm
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
        python3 \
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
        telnet \
        which \
      && \
    yum -y clean all && \
    update-alternatives --set python /usr/bin/python3 && \
    rm -rf /rpm /etc/yum.repos.d/arkcase.repo

#
# Declare some important volumes
#
VOLUME /app/conf
VOLUME /app/init
VOLUME /var/log/samba
VOLUME /var/lib/samba

EXPOSE 389
EXPOSE 636

#
# Set up script and run
#
COPY --chown=root:root entrypoint test-ready.sh test-live.sh test-startup.sh samba-directory-templates.tar.gz /
RUN chmod 755 /entrypoint /test-ready.sh /test-live.sh /test-startup.sh

HEALTHCHECK CMD /test-ready.sh

ENTRYPOINT [ "/entrypoint" ]
