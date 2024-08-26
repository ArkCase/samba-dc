#!/bin/bash

set -euo pipefail
. /.functions

define_base_vars

DEBUG="$(to_boolean "${DEBUG:-false}")"

${DEBUG} && set -x

#
# Set and normalize variables
#
[ -v BASE_DIR ] || BASE_DIR=""
[ -n "${BASE_DIR}" ] || BASE_DIR="/app"

[ -v SECRETS_DIR ] || SECRETS_DIR=""
[ -n "${SECRETS_DIR}" ] || SECRETS_DIR="${BASE_DIR}/secrets"

[ -v DOMAIN ] || DOMAIN=""
[ -n "${DOMAIN}" ] || DOMAIN="$(<"${SECRETS_DIR}/DOMAIN_NAME)")"

#
# This function will check to see if the instance can be considered
# "configured"
#
is_initialized()
{
	local CANDIDATES=()

	#
	# Common data
	#
	CANDIDATES+=("account_policy.tdb")
	CANDIDATES+=("netsamlogon_cache.tdb")
	CANDIDATES+=("registry.tdb")
	CANDIDATES+=("share_info.tdb")
	CANDIDATES+=("smbprofile.tdb")
	CANDIDATES+=("winbindd_cache.tdb")
	CANDIDATES+=("wins.ldb")

	#
	# Private data
	#
	CANDIDATES+=("private/dns_update_cache")
	CANDIDATES+=("private/dns_update_list")
	CANDIDATES+=("private/encrypted_secrets.key")
	CANDIDATES+=("private/hklm.ldb")
	CANDIDATES+=("private/idmap.ldb")
	CANDIDATES+=("private/kdc.conf")
	CANDIDATES+=("private/krb5.conf")
	CANDIDATES+=("private/netlogon_creds_cli.tdb")
	CANDIDATES+=("private/privilege.ldb")
	CANDIDATES+=("private/sam.ldb")
	CANDIDATES+=("private/schannel_store.tdb")
	CANDIDATES+=("private/secrets.keytab")
	CANDIDATES+=("private/secrets.ldb")
	CANDIDATES+=("private/secrets.tdb")
	CANDIDATES+=("private/share.ldb")
	CANDIDATES+=("private/spn_update_list")
	CANDIDATES+=("private/wins_config.ldb")

	#
	# SSL Certificates
	#
	CANDIDATES+=("private/tls/ca.pem")
	CANDIDATES+=("private/tls/cert.pem")
	CANDIDATES+=("private/tls/key.pem")

	#
	# Domain configurations
	#
	CANDIDATES+=("private/sam.ldb.d/metadata.tdb")

	#
	# Temporarily turned off due to behavioral change on the O/S.
	#
	# For some reason, these names are now being URL-encoded (i.e.
	# the "=" sign goes to "%3D" and the "," goes to "%2C"). This
	# wasn't happening before ... we could support both, but that
	# would require significant logic upgrades which, honestly,
	# aren't worth the time right now.
	#
	# We would need to support both since this code would have to
	# work for both old deployments with the old names, and new
	# ones with the URL-encoded names. Thus, for now, screw it! :)
	#
	# CANDIDATES+=("private/sam.ldb.d/CN=CONFIGURATION,${DC}.ldb")
	# CANDIDATES+=("private/sam.ldb.d/CN=SCHEMA,CN=CONFIGURATION,${DC}.ldb")
	# CANDIDATES+=("private/sam.ldb.d/DC=DOMAINDNSZONES,${DC}.ldb")
	# CANDIDATES+=("private/sam.ldb.d/DC=FORESTDNSZONES,${DC}.ldb")
	# CANDIDATES+=("private/sam.ldb.d/${DC}.ldb")

	#
	# Check for the created databases
	#
	local PFX="/var/lib/samba"
	for C in "${CANDIDATES[@]}" ; do
		C="${PFX}/${C}"
		[ -e "${C}" ] || return 1
		[ -f "${C}" ] || return 1
		[ -r "${C}" ] || return 1
	done

	#
	# Domain Policies
	#
	local POLICY_DIR="${PFX}/sysvol/${DOMAIN,,}/Policies"
	[ -e "${POLICY_DIR}" ] || return 1
	[ -d "${POLICY_DIR}" ] || return 1
	[ -r "${POLICY_DIR}" ] || return 1
	[ -x "${POLICY_DIR}" ] || return 1

	#
	# Is this correct? Can a domain exist with no policies?
	#
	# TODO: disabled for now, as additional DCs don't seem to copy them over
	#local POLICIES=$(find "${POLICY_DIR}" -type f -iname GPT.INI | wc -l)
	#[ "${POLICIES}" -lt 1 ] && return 1

	#
	# We're fully configured, so we don't have to redo it
	#
	return 0
}

${DEBUG} && set -x
is_initialized
RC=${?}
${DEBUG} && set +x
if [ ${RC} -ne 0 ] ; then
	echo -e "This instance isn't initialized properly"
	exit 1
fi

# All appears to be well ... but are we really ready?
echo -e "The instance is ready"
exec "${__BASEDIR}/test-live.sh"
