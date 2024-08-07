#!/bin/bash
SCRIPT="$(readlink -f "${BASH_SOURCE:-${0}}")"
BASEDIR="$(dirname "${SCRIPT}")"
SCRIPT="$(basename "${SCRIPT}")"

[ -v SECRETS_DIR ] || SECRETS_DIR=""
[ -n "${SECRETS_DIR}" ] || SECRETS_DIR="/app/secrets"
export SECRETS_DIR

read_setting()
{
	local SETTING="${1}"
	local DEFAULT="${2:-}"

	local RESULT="${DEFAULT}"

	if [ -v "${SETTING}" ] ; then
		# It's an envvar!! use it!
		RESULT="${!SETTING}"
	elif [ -d "${SECRETS_DIR}" ] ; then
		# No envvar? What about a secret file?
		local FILE="${SECRETS_DIR}/${SETTING}"
		[ -e "${FILE}" ] && [ -f "${FILE}" ] && [ -r "${FILE}" ] && RESULT="$(<"${FILE}")"
	fi

	# Return the final value
	echo -en "${RESULT}"
	exit 0
}

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

REALM="$(read_setting "DOMAIN_REALM")"
ROOT_DN="$(read_setting "DOMAIN_ROOT_DN")"
USERNAME="$(read_setting "DOMAIN_USERNAME" "Administrator")"
PASSWORD="$(read_setting "DOMAIN_PASSWORD")"

${DEBUG} && set -x
OUT="$(ldapsearch -H ldaps://localhost -D "${REALM}\\${USERNAME}" -y <(echo -n "${PASSWORD}") -s one -b "${ROOT_DN}" "(objectClass=organizationalUnit)" dn 2>&1)"
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
