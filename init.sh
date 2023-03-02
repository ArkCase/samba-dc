#!/bin/bash

set -euo pipefail

say() {
	echo -e "${@}"
}

fail() {
	say "${@}" 1>&2
	exit ${EXIT_CODE:-1}
}

DEBUG="false"
case "${DEBUG,,}" in
	true | t | yes | y | 1 | on | active | enabled ) DEBUG="true" ;;
esac

${DEBUG} && set -x

[ -v BASE_DIR ] || BASE_DIR="/app"
[ -v INIT_DIR ] || INIT_DIR="${BASE_DIR}/init"
[ -v CONF_DIR ] || CONF_DIR="${BASE_DIR}/conf"

SUPERVISOR_SMB_CONF="/etc/supervisord.d/samba-dc.ini"
SUPERVISOR_VPN_CONF="/etc/supervisord.d/samba-vpn.ini"
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

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

backup_file() {
	local FILE="${1}"
	[ -f "${FILE}" ] && mv -vf "${FILE}" "${FILE}.bak-${TIMESTAMP}"
	return 0
}

ini_list_sections() {
	local FILE="${1}"
	[ -z "${FILE}" ] && return 1
	grep "^[[:space:]]*\[[^\]\+]" "${FILE}" | sed -e 's/^\s*\[//g' -e 's/\].*$//g'
}

ini_has_section() {
	local FILE="${1}"
	local SECTION="${2}"
	[ -z "${FILE}" ] && return 1
	[ -z "${SECTION}" ] && return 1
	ini_list_sections "${FILE}" | grep -q "${SECTION}"
}

ini_get_value() {
	local FILE="${1}"
	local SECTION="${2}"
	local KEY="${3}"
	[ -z "${FILE}" ] && return 1
	[ -z "${SECTION}" ] && return 1
	[ -z "${KEY}" ] && return 1
	ini_has_section "${FILE}" "${SECTION}" || return 1
	local KVP="$(sed -nr "/^\s*\[${SECTION}\]/,/\[/{/^\s*${KEY}\s*=/p}" "${FILE}" | tail -1)"
	echo "${KVP#*=}" | sed -e 's;^[[:space:]]*;;g' -e 's;[[:space:]]*$;;g'
}

reset_data() {
	say "Cleaning up any vestigial configurations"
	rm -rf /var/lib/samba/* /var/log/samba/*
	tar -C / -xzf /samba-directory-templates.tar.gz
}

#
# This function will check to see if the instance can be considered
# "configured"
#
is_initialized() {
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
	CANDIDATES+=("private/sam.ldb.d/CN=CONFIGURATION,${DC}.ldb")
	CANDIDATES+=("private/sam.ldb.d/CN=SCHEMA,CN=CONFIGURATION,${DC}.ldb")
	CANDIDATES+=("private/sam.ldb.d/DC=DOMAINDNSZONES,${DC}.ldb")
	CANDIDATES+=("private/sam.ldb.d/DC=FORESTDNSZONES,${DC}.ldb")
	CANDIDATES+=("private/sam.ldb.d/${DC}.ldb")

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
	say "Domain data is already configured"
	return 0
}

cfg_mismatch() {
	local L="${1}"
	local R1="${2}"
	local R2="${3}"

	say "The existing configurations are for the ${L} [${R1}]"
	say "This container instance has been configured for the ${L} [${R2}]"
	say "This mismatch is unresolvable - please manually clean out the existing data files and logs, or fix the configuration file"
}

check_krb_conf() {
	[ -f "${EXT_KRB_CONF}" ] || return 1

	local EXT_DOMAIN="$(ini_get_value "${EXT_KRB_CONF}" "libdefaults" "default_realm")"
	[ "${EXT_DOMAIN^^}" = "${DOMAIN^^}" ] || { cfg_mismatch "kerberos realm" "${EXT_DOMAIN}" "${DOMAIN}" ; exit 1 ; }

	return 0
}

check_smb_conf() {
	[ -f "${EXT_SMB_CONF}" ] || return 1

	local EXT_REALM="$(ini_get_value "${EXT_SMB_CONF}" "global" "workgroup")"
	[ "${EXT_REALM^^}" = "${REALM^^}" ] || { cfg_mismatch "realm" "${EXT_REALM}" "${REALM}" ; exit 1 ; }

	local EXT_DOMAIN="$(ini_get_value "${EXT_SMB_CONF}" "global" "realm")"
	[ "${EXT_DOMAIN^^}" = "${DOMAIN^^}" ] || { cfg_mismatch "domain" "${EXT_DOMAIN}" "${DOMAIN}" ; exit 1 ; }

	return 0
}

configure_krb() {
	if check_krb_conf ; then
		cp -f "${EXT_KRB_CONF}" "${KRB_CONF}"
		return 0
	fi

	#
	# Configure Kerberos
	#
	mv "${KRB_CONF}" "${KRB_CONF}".orig
	cat <<-EOF > "${KRB_CONF}"
		[libdefaults]
		dns_lookup_realm = false
		dns_lookup_kdc = true
		default_realm = ${UDOMAIN}
	EOF

	backup_file "${EXT_KRB_CONF}"
	cp -f "${KRB_CONF}" "${EXT_KRB_CONF}"

	return 0
}

configure_smb() {
	if check_smb_conf ; then
		cp -f "${EXT_SMB_CONF}" "${SMB_CONF}"
		return 0
	fi

	is_initialized && return 0

	say "Configuring the domain"

	# Should we do this?
	reset_data

	# If multi-site, we need to connect to the VPN before joining the domain
	if [ "${MULTISITE,,}" == "true" ]; then
		/usr/sbin/openvpn --config /docker.ovpn &
		VPNPID="${!}"
		# TODO: Find a more efficient way to do this?
		say "Sleeping 30s to ensure VPN connects (${VPNPID})";
		sleep 30
	fi

	# Set host ip option
	HOSTIP_OPTION=""
	[ "${HOSTIP}" != "NONE" ] && HOSTIP_OPTION="--host-ip=${HOSTIP}"

	# If the finished file isn't there, this is brand new, we're not just moving to a new container
	mv "${SMB_CONF}" "${SMB_CONF}.orig"
	if [ "${JOIN,,}" == "true" ]; then
		if [ "${JOINSITE}" == "NONE" ]; then
			samba-tool domain join "${LDOMAIN}" DC -U"${REALM}\\administrator" --password="${DOMAINPASS}" --dns-backend=SAMBA_INTERNAL
		else
			samba-tool domain join "${LDOMAIN}" DC -U"${REALM}\\administrator" --password="${DOMAINPASS}" --dns-backend=SAMBA_INTERNAL --site="${JOINSITE}"
		fi
	else
		PROVISION_FLAGS=()
		[ -n "${HOSTIP_OPTION}" ] && PROVISION_FLAGS+=("${HOSTIP_OPTION}")
		samba-tool domain provision --use-rfc2307 --domain="${REALM}" --realm="${UDOMAIN}" --server-role=dc --dns-backend=SAMBA_INTERNAL --adminpass="${DOMAINPASS}" "${PROVISION_FLAGS[@]}"
		if [[ ${NOCOMPLEXITY,,} == "true" ]]; then
			samba-tool domain passwordsettings set --complexity=off
			samba-tool domain passwordsettings set --history-length=0
			samba-tool domain passwordsettings set --min-pwd-age=0
			samba-tool domain passwordsettings set --max-pwd-age=0
		fi
	fi
	sed -i "/\[global\]/a \
		\\\tidmap_ldb:use rfc2307 = yes\\n\
		wins support = yes\\n\
		template shell = /bin/bash\\n\
		winbind nss info = rfc2307\\n\
		idmap config ${REALM}: range = 10000-20000\\n\
		idmap config ${REALM}: backend = ad\
		" "${SMB_CONF}"
	if [ "${DNSFORWARDER}" != "NONE" ]; then
		sed -i "/\[global\]/a \
			\\\tdns forwarder = ${DNSFORWARDER}\
			" "${SMB_CONF}"
	fi
	if [ "${INSECURELDAP,,}" == "true" ]; then
		sed -i "/\[global\]/a \
			\\\tldap server require strong auth = no\
			" "${SMB_CONF}"
	fi
	# Once we are set up, we'll make a file so that we know to use it if we ever spin this up again
	backup_file "${EXT_SMB_CONF}"
	cp -f "${SMB_CONF}" "${EXT_SMB_CONF}"

	# Apply extra initializations, if needed
	local INIT_SCRIPTS="${INIT_DIR}/init.d"
	if [ -d "${INIT_SCRIPTS}" ] ; then
		say "Launching extra initializations from [${INIT_SCRIPTS}]..."
		cd "${INIT_SCRIPTS}" || exit 1
		while read script ; do
			say "\tLaunching the extra initializer script [${script}]..."
			if ! "$(readlink -f "${script}")" ; then
				say "\tError executing the initializer script [${script}] (rc=${?})"
				return 1
			fi
		done < <(find . -mindepth 1 -maxdepth 1 -type f -perm /u+x | sort | sed -e 's;^./;;g')
	fi

	say "Initialization complete"
	return ${?}
}

configure_k8s() {
	local DNS_IP=""
	
	[ -n "${KUBERNETES_SERVICE_HOST}" ] || return 1

	# We've been explicitly told who our forwarder is, so we don't use it
	# TODO: Support setting a name here that can be looked up via K8s DNS
	#       perhaps by checking to see if we've been given an IP address
	#       or a hostname?
	[ -n "${DNSFORWARDER}" ] && return 0

	# Lookup the DNS name kube-dns.kube-system.svc.cluster.local
	# TODO: Handle cases when the cluster domain is something else
	local CLUSTER_DOMAIN="cluster.local"
	local K8S_DNS="$(dig +short "kube-dns.kube-system.svc.${CLUSTER_DOMAIN}")"
	[ -n "${K8S_DNS}" ] || return 1

	DNSFORWARDER="${K8S_DNS}"
}

# In case we're in Kubernetes
configure_k8s || say "Kubernetes configurations not available"

#
# Configure the components
#
configure_krb
if ! configure_smb ; then
	reset_data
	fail "Failed to configure Samba"
fi

#
# Set up supervisor
#
# We don't care if this is an old or new container ... we do it anyway to ensure
# configuration consistency
#
cat <<-EOF > "${SUPERVISOR_SMB_CONF}"
[program:samba]
command=/usr/sbin/samba -i
EOF

if [ "${MULTISITE,,}" = "true" ] ; then
	[ -n "${VPNPID}" ] kill "${VPNPID}"
	cat <<-EOF > "${SUPERVISOR_VPN_CONF}"
	[program:openvpn]
	command=/usr/sbin/openvpn --config /docker.ovpn
	EOF
else
	rm -f "${SUPERVISOR_VPN_CONF}" &>/dev/null
fi

#
# Deploy the new certificates
#
[ -v LDAP_SSL_BASE ] || LDAP_SSL_BASE="${INIT_DIR}/ssl"
[ -v LDAP_SSL_CA ] || LDAP_SSL_CA="${LDAP_SSL_BASE}/ca.pem"
[ -v LDAP_SSL_CERT ] || LDAP_SSL_CERT="${LDAP_SSL_BASE}/cert.pem"
[ -v LDAP_SSL_KEY ] || LDAP_SSL_KEY="${LDAP_SSL_BASE}/key.pem"

LOCAL_CERT_HOME="/var/lib/samba/private/tls"

DEPLOY_CERTS="false"
if [ -d "${LDAP_SSL_BASE}" ] ; then
	# If there's a certificate, make sure there's also a key
	if [ -f "${LDAP_SSL_CERT}" ] && [ -f "${LDAP_SSL_KEY}" ] ; then
		say "New certificates identified - validating them for use"
		# If there's both a certificate and a key, make sure they match
		CERT_MOD="$(openssl x509 -noout -modulus -inform pem -in "${LDAP_SSL_CERT}")"
		[ -n "${CERT_MOD}" ] && CERT_MD5="$(openssl md5 < <(echo -n "${CERT_MOD}"))"

		KEY_MOD="$(openssl rsa -noout -modulus -passin /dev/null -inform pem -in "${LDAP_SSL_KEY}")"
		[ -n "${KEY_MOD}" ] && KEY_MD5="$(openssl md5 < <(echo -n "${KEY_MOD}"))"

		# If the MD5s have been computed, it's b/c the cert and key are there for that to happen
		if [ -v KEY_MD5 ] && [ -v CERT_MD5 ] && [ "${KEY_MD5}" == "${CERT_MD5}" ] ; then
			# Disable deployment if we were given a CA that doesn't match the given certificate
			TEST_CA="${LDAP_SSL_CA}"
			[ -f "${TEST_CA}" ] || TEST_CA="${LOCAL_CERT_HOME}/ca.pem"

			if [ -f "${TEST_CA}" ] && ! openssl verify -CAfile "${TEST_CA}" "${LDAP_SSL_CERT}" &>/dev/null ; then
				say "Certification Authority check failed for the new certificates (CA=${TEST_CA})- will not deploy them"
				DEPLOY_CERTS="false"
			else
				# Everything matched, and either the CA test succeeded, or there was no CA to check against
				DEPLOY_CERTS="true"
			fi
		else
			say "Modulus check failed for the new certificates - will not deploy them"
		fi
	fi
fi

# If all these checks succeed, deploy the new certificates, removing existing files
if ${DEPLOY_CERTS} ; then
	say "New certificates were verified"
	say "Removing the old certificates from [${LOCAL_CERT_HOME}]"
	rm -f "${LOCAL_CERT_HOME}"/* &>/dev/null
	say "Deploying the new certificates to [${LOCAL_CERT_HOME}]"
	cp -vf "${LDAP_SSL_CERT}" "${LOCAL_CERT_HOME}/cert.pem"
	cp -vf "${LDAP_SSL_KEY}" "${LOCAL_CERT_HOME}/key.pem"

	# This is the only piece of the puzzle that's optional
	[ -n "${LDAP_SSL_CA}" ] && cp -vf "${LDAP_SSL_CA}" "${LOCAL_CERT_HOME}/ca.pem"
fi

say "Launching Samba (via supervisord)"
exec /usr/bin/supervisord -n
