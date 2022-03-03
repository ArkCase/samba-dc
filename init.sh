#!/bin/bash

set -e

SUPERVISOR_SAMBA_CONF="/etc/supervisord.d/samba-dc.ini"
SUPERVISOR_OPENVPN_CONF="/etc/supervisord.d/openvpn.ini"
EXT_CONF="/etc/samba/external/smb.conf"

configure () {

	# Set variables
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

	# If the finished file isn't there, this is brand new, we're not just moving to a new container
	if [ ! -f "${EXT_CONF}" ]; then
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
		cp /etc/samba/smb.conf "${EXT_CONF}"
	else
		cp "${EXT_CONF}" /etc/samba/smb.conf
	fi
        
	# Set up supervisor
	cat <<-EOF > "${SUPERVISOR_SAMBA_CONF}"
	[program:samba]
	command=/usr/sbin/samba -i
	EOF

	if [ "${MULTISITE,,}" == "true" ]; then
		[ -n "${VPNPID}" ] kill "${VPNPID}"
		cat <<-EOF > "${SUPERVISOR_OPENVPN_CONF}"
		[program:openvpn]
		command=/usr/sbin/openvpn --config /docker.ovpn
		EOF
	fi
}

# If the supervisor conf isn't there, we're spinning up a new container
[ -f "${SUPERVISOR_SAMBA_CONF}" ] || configure
exec /usr/bin/supervisord -n
