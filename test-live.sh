#!/bin/bash
SCRIPT="$(readlink -f "${BASH_SOURCE:-${0}}")"
BASEDIR="$(dirname "${SCRIPT}")"
SCRIPT="$(basename "${SCRIPT}")"

DEBUG="false"
case "${DEBUG,,}" in
	true | t | yes | y | 1 | on | active | enabled ) DEBUG="true" ;;
esac

${DEBUG} && set -x
OUT="$(samba-tool processes --name=ldap_server 2>&1)"
RC=${?}
${DEBUG} && set +x
if [ ${RC} -ne 0 ] ; then
	echo -e "Failed to verify the Samba process status"
	echo -e "${OUT}"
	exit 1
fi
if [ -n "${OUT}" ] ; then
	echo -e "No Samba ldap_server processes were found"
	exit 1
fi
${DEBUG} && echo -e "${OUT}"

echo -e "The instance is live"
exit 0
