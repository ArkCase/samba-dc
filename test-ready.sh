#!/bin/bash
SCRIPT="$(readlink -f "${BASH_SOURCE:-${0}}")"
BASEDIR="$(dirname "${SCRIPT}")"
SCRIPT="$(basename "${SCRIPT}")"

DEBUG="false"
case "${DEBUG,,}" in
	true | t | yes | y | 1 | on | active | enabled ) DEBUG="true" ;;
esac

#${DEBUG} && set -x

CONF_DIR="/config"
SMB_CONF="/etc/samba/smb.conf"
EXT_SMB_CONF="${CONF_DIR}/smb.conf"
KRB_CONF="/etc/krb5.conf"
EXT_KRB_CONF="${CONF_DIR}/krb5.conf"

#
# Set and normalize variables
#
DOMAINPASS="${DOMAINPASS:-youshouldsetapassword}"
JOIN="${JOIN:-false}"
JOINSITE="${JOINSITE:-NONE}"
MULTISITE="${MULTISITE:-false}"
NOCOMPLEXITY="${NOCOMPLEXITY:-false}"
INSECURELDAP="${INSECURELDAP:-false}"
DNSFORWARDER="${DNSFORWARDER:-NONE}"
HOSTIP="${HOSTIP:-NONE}"

DOMAIN="${DOMAIN:-SAMDOM.LOCAL}"
LDOMAIN="${DOMAIN,,}"
UDOMAIN="${DOMAIN^^}"
REALM="${UDOMAIN%%.*}"

D2=()
IFS="." D2=(${DOMAIN})
D3=()
for P in "${D2[@]}" ; do
	D3+=("DC=${P^^}")
done

DC=""
for P in "${D3[@]}" ; do
	[ -n "${DC}" ] && DC="${DC},"
	DC="${DC}${P}"
done
unset D2 D3

${DEBUG} && set -x
OUT="$(openssl s_client -connect localhost:636 -showcerts </dev/null 2>&1)"
RC=${?}
${DEBUG} && set +x
if [ ${RC} -ne 0 ] ; then
	echo -e "Failed to get the SSL certificates from the LDAPS server"
	echo -e "${OUT}"
	exit 1
fi
echo -e "Port 636/tcp seems to be listening and serving out certificates"
${DEBUG} && echo -e "${CERTS}"

# TODO: Do we want to validate the certificate?
export LDAPTLS_REQCERT="never"

${DEBUG} && set -x
OUT="$(ldapsearch -H ldaps://localhost:636 -D "${REALM}\\administrator" -w "${DOMAINPASS}" -b "${DC}" '(objectClass=user)' dn 2>&1)"
RC=${?}
${DEBUG} && set +x
if [ ${RC} -ne 0 ] ; then
	echo -e "Failed to execute a test LDAPS query"
	echo -e "${OUT}"
	exit 1
fi
echo -e "LDAP Search successful"
${DEBUG} && echo -e "${OUT}"

# All appears to be well!
echo -e "The instance is live"
exit 0
