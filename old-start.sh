#!/bin/bash

set -eu -o pipefail

echo "Running samba start script."

# Setting environment variables
DNS_FORWARDER=$(grep ^nameserver /etc/resolv.conf | sed 's/nameserver //')

# Stage /app/samba/etc/smb.conf file
cat > /app/samba/etc/smb.conf <<EOF
# Global parameters
[global]
  log level = 1
  log file = /dev/stdout
  dns forwarder = ${DNS_FORWARDER}
  netbios name = $(hostname)
  realm = ${SAMBA_REALM}
  server services = dns, s3fs, rpc, wrepl, ldap, cldap, kdc, drepl, winbindd, ntp_signd, kcc, dnsupdate
  server role = active directory domain controller
  workgroup = ${SAMBA_DOMAIN}
  idmap_ldb:use rfc2307 = yes
  smb ports = 445
[sysvol]
  path = /app/samba/var/locks/sysvol
  read only = No
[netlogon]
  path = /app/samba/var/locks/sysvol/${SAMBA_REALM}/scripts
  read only = No
EOF

# Create domain
# TODO: why do you need to run the initialization (create configuration, DNS zones, etc) every time the container is started? Shouldn't you somehow test to see if this is needed?
/app/samba/bin/samba-tool domain provision \
--realm="${SAMBA_REALM}" \
--domain="${SAMBA_DOMAIN}" \
--adminpass="${SAMBA_ADMIN_PASSWORD}" \
--server-role="dc" \
--dns-backend="SAMBA_INTERNAL" \
--use-rfc2307 \
--function-level="2008_R2"

# krb5.conf is created by the command above, copy it to where it needs to be
\cp -pf /app/samba/private/krb5.conf /etc/krb5.conf

# Update /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo "search ${SAMBA_REALM}" >> /etc/resolv.conf

# Start Samba, samba needs to be running for the samba-tool commands after to be successful
/app/samba/sbin/samba

sleep 0.5

# Get octets of the IP address and store them in environment variables for reverse DNS creation
CIDR=$(ip -o a show dev "eth0" | awk '{ print $4 }')
IP="${CIDR/\/*}"
read IP_OCTET_1 IP_OCTET_2 IP_OCTET_3 IP_OCTET_4 < <(echo "${IP//./ }")

if [ -n "$(dig -t SOA ${IP_OCTET_3}.${IP_OCTET_2}.${IP_OCTET_1}.in-addr.arpa. @${IP} +short)" ] ; then
  echo 'Reverse DNS zone already exists'
else
  echo 'Creating Reverse DNS zone';

  # Create IPv4 reverse lookup zone
  /app/samba/bin/samba-tool dns zonecreate --username='Administrator' --password="${SAMBA_ADMIN_PASSWORD}" ${SAMBA_REALM} ${IP_OCTET_3}.${IP_OCTET_2}.${IP_OCTET_1}.in-addr.arpa
  /app/samba/bin/samba-tool dns add --username='Administrator' --password="${SAMBA_ADMIN_PASSWORD}" $(hostname).${SAMBA_REALM} ${IP_OCTET_3}.${IP_OCTET_2}.${IP_OCTET_1}.in-addr.arpa 15 PTR $(hostname).${SAMBA_REALM}
fi

# set administrator password to never expire
/app/samba/bin/samba-tool user setexpiry Administrator --noexpiry

# Stop Samba background process
iterations=0
while kill -TERM $(cat /app/samba/var/run/samba.pid) > /dev/null 2>&1; do
    # limit this loop to 30 seconds total
    ((iterations++)) && ((iterations==6)) && break
    sleep 5
done

if (test -f "/app/samba/var/run/samba.pid") && (ps -p $(cat /app/samba/var/run/samba.pid) > /dev/null); then
  cat /app/samba/var/run/samba.pid
  kill -9 $(cat /app/samba/var/run/samba.pid)
fi

# Configure LDAP client settings to test LDAP server
cat > /etc/openldap/ldap.conf <<EOF
#
# LDAP Defaults
#
# See ldap.conf(5) for details
# This file should be world readable but not world writable.
HOST   $(hostname).${SAMBA_REALM}
BASE   dc=${SAMBA_DOMAIN},dc=net
URI    ldap://$(hostname).${SAMBA_REALM} ldaps://$(hostname).${SAMBA_REALM}:636
#SIZELIMIT      12
#TIMELIMIT      15
#DEREF          never
TLS_CACERTDIR   /etc/openldap/certs
# Turning this off breaks GSSAPI used with krb5 when rdns = false
SASL_NOCANON    on
EOF

# Start samba in the foreground (for logging and to keep the container running)
exec /app/samba/sbin/samba --foreground
