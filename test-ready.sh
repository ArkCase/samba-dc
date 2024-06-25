#!/bin/bash
SCRIPT="$(readlink -f "${BASH_SOURCE:-${0}}")"
BASEDIR="$(dirname "${SCRIPT}")"
SCRIPT="$(basename "${SCRIPT}")"

[ -v SECRETS_DIR ] || SECRETS_DIR=""
[ -n "${SECRETS_DIR}" ] || SECRETS_DIR="/app/secrets"
export SECRETS_DIR

DEBUG="false"
case "${DEBUG,,}" in
	true | t | yes | y | 1 | on | active | enabled ) DEBUG="true" ;;
esac
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
${DEBUG} && echo -e "${OUT}"

${DEBUG} && set -x
OUT="$(ldapsearch -H ldaps://localhost -D "$(<"${SECRETS_DIR}/DOMAIN_REALM")\\Administrator" -y "${SECRETS_DIR}/DOMAIN_PASSWORD" -s one -b "$(<"${SECRETS_DIR}/DOMAIN_ROOT_DN")" "(objectClass=organizationalUnit)" dn 2>&1)"
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
echo -e "The instance is ready"
exit 0
