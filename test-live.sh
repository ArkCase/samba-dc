#!/bin/bash
SCRIPT="$(readlink -f "${BASH_SOURCE:-${0}}")"
BASEDIR="$(dirname "${SCRIPT}")"
SCRIPT="$(basename "${SCRIPT}")"

DEBUG="false"
case "${DEBUG,,}" in
	true | t | yes | y | 1 | on | active | enabled ) DEBUG="true" ;;
esac

${DEBUG} && set -x
OUT="$(supervisorctl status samba 2>&1)"
RC=${?}
${DEBUG} && set +x
if [ ${RC} -ne 0 ] ; then
	echo -e "Failed to verify the Samba process status"
	echo -e "${OUT}"
	exit 1
fi
echo -e "SupervisorD reports the Samba process as running"
${DEBUG} && echo -e "${OUT}"

echo -e "The instance is live"
exit 0
