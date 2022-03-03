#!/bin/bash

set -e -o pipefail

DEBUG="false"
case "${DEBUG,,}" in
	true | t | yes | y | 1 | on | active | enabled ) DEBUG="true" ;;
esac

${DEBUG} && set -x

CONF_DIR="/config"
SUPERVISOR_SAMBA_CONF="/etc/supervisord.d/samba-dc.ini"
SUPERVISOR_OPENVPN_CONF="/etc/supervisord.d/openvpn.ini"
EXT_SMB_CONF="${CONF_DIR}/smb.conf"
EXT_KRB_CONF="${CONF_DIR}/krb5.conf"

#
# Set and normalize variables
#
DOMAIN="${DOMAIN:-SAMDOM.LOCAL}"
DOMAINPASS="${DOMAINPASS:-youshouldsetapassword}"
JOIN="${JOIN:-false}"
JOINSITE="${JOINSITE:-NONE}"
MULTISITE="${MULTISITE:-false}"
NOCOMPLEXITY="${NOCOMPLEXITY:-false}"
INSECURELDAP="${INSECURELDAP:-false}"
DNSFORWARDER="${DNSFORWARDER:-NONE}"
HOSTIP="${HOSTIP:-NONE}"

LDOMAIN="${DOMAIN,,}"
UDOMAIN="${DOMAIN^^}"
URDOMAIN="${UDOMAIN%%.*}"

IFS="." D2=(${DOMAIN})
D3=()
for P in "${D2[@]}" ; do
	D3+=("DC=${P^^}")
done
unset D2

DC=""
for P in "${D3[@]}" ; do
	[ -n "${DC}" ] && DC="${DC},"
	DC="${DC}${P}"
done
unset D3

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

backup_file() {
	local FILE="${1}"
	[ -f "${FILE}" ] && mv -vf "${FILE}" "${FILE}.bak-${TIMESTAMP}"
	return 0
}

#
# This function will check to see if the instance can be considered
# "configured"
#
is_configured() {
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
	local POLICIES=$(find "${POLICY_DIR}" -type f -iname GPT.INI | wc -l)
	[ "${POLICIES}" -lt 1 ] && return 1

	#
	# We're fully configured, so we don't have to redo it
	#
	echo "Domain data is already configured"
	return 0
}


if ! is_configured ; then

	# Should we do this?
	echo "Cleaning up any vestigial configurations"
	rm -rf /var/lib/samba/* /var/log/samba/*
	tar -C / -xzf /samba-directory-templates.tar.gz

	echo "Configuring the domain"

	# If multi-site, we need to connect to the VPN before joining the domain
	if [ "${MULTISITE,,}" == "true" ]; then
		/usr/sbin/openvpn --config /docker.ovpn &
		VPNPID="${!}"
		# TODO: Find a more efficient way to do this?
		echo "Sleeping 30s to ensure VPN connects (${VPNPID})";
		sleep 30
	fi

	# Set host ip option
	HOSTIP_OPTION=""
	[ "${HOSTIP}" != "NONE" ] && HOSTIP_OPTION="--host-ip=${HOSTIP}"

	# Set up samba
	mv /etc/krb5.conf /etc/krb5.conf.orig
	cat <<-EOF > /etc/krb5.conf
	[libdefaults]
	dns_lookup_realm = false
	dns_lookup_kdc = true
	default_realm = ${UDOMAIN}
	EOF
	backup_file "${EXT_KRB_CONF}"
	cp /etc/krb5.conf "${EXT_KRB_CONF}"

	# If the finished file isn't there, this is brand new, we're not just moving to a new container
	mv /etc/samba/smb.conf /etc/samba/smb.conf.orig
	if [ "${JOIN,,}" == "true" ]; then
		if [ "${JOINSITE}" == "NONE" ]; then
			samba-tool domain join "${LDOMAIN}" DC -U"${URDOMAIN}\\administrator" --password="${DOMAINPASS}" --dns-backend=SAMBA_INTERNAL
		else
			samba-tool domain join "${LDOMAIN}" DC -U"${URDOMAIN}\\administrator" --password="${DOMAINPASS}" --dns-backend=SAMBA_INTERNAL --site="${JOINSITE}"
		fi
	else
		PROVISION_FLAGS=()
		[ -n "${HOSTIP_OPTION}" ] && PROVISION_FLAGS+=("${HOSTIP_OPTION}")
		samba-tool domain provision --use-rfc2307 --domain="${URDOMAIN}" --realm="${UDOMAIN}" --server-role=dc --dns-backend=SAMBA_INTERNAL --adminpass="${DOMAINPASS}" "${PROVISION_FLAGS[@]}"
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
		idmap config ${URDOMAIN}: range = 10000-20000\\n\
		idmap config ${URDOMAIN}: backend = ad\
		" /etc/samba/smb.conf
	if [ "${DNSFORWARDER}" != "NONE" ]; then
		sed -i "/\[global\]/a \
			\\\tdns forwarder = ${DNSFORWARDER}\
			" /etc/samba/smb.conf
	fi
	if [ "${INSECURELDAP,,}" == "true" ]; then
		sed -i "/\[global\]/a \
			\\\tldap server require strong auth = no\
			" /etc/samba/smb.conf
	fi
	# Once we are set up, we'll make a file so that we know to use it if we ever spin this up again
	backup_file "${EXT_SMB_CONF}"
	cp /etc/samba/smb.conf "${EXT_SMB_CONF}"
fi

#
# Apply the external configurations
#
cp "${EXT_SMB_CONF}" /etc/samba/smb.conf

#
# TODO: do we want to add Kerberos (krb5.conf) here? Samba has one ...
#
cp "${EXT_KRB_CONF}" /etc/krb5.conf

#
# Set up supervisor
#
# We don't care if this is an old or new container ... we do it anyway to ensure
# configuration consistency
#
cat <<-EOF > "${SUPERVISOR_SAMBA_CONF}"
[program:samba]
command=/usr/sbin/samba -i
EOF

if [ "${MULTISITE,,}" = "true" ] ; then
	[ -n "${VPNPID}" ] kill "${VPNPID}"
	cat <<-EOF > "${SUPERVISOR_OPENVPN_CONF}"
	[program:openvpn]
	command=/usr/sbin/openvpn --config /docker.ovpn
	EOF
else
	rm -f "${SUPERVISOR_OPENVPN_CONF}" &>/dev/null
fi
exec /usr/bin/supervisord -n
