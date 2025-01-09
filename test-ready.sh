#!/bin/bash

set -euo pipefail
. /.functions

DEBUG="$(to_boolean "${DEBUG:-false}")"

set_or_default BASE_DIR "/app"
set_or_default SECRETS_DIR "${BASE_DIR}/secrets"
export SECRETS_DIR

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

ROOT_DN="$(read_setting "DOMAIN_ROOT_DN")"

${DEBUG} && set -x
OUT="$(search -s one -b "${ROOT_DN}" "(objectClass=organizationalUnit)" dn 2>&1)"
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
