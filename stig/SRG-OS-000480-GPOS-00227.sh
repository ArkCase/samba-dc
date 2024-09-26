#!/bin/bash
set -euo pipefail

cat <<-EOF
STIG Remediation script for:

anssi    R31
cis      enable_authselect
disa     CCI-000213
hipaa    164.308(a)(1)(ii)(B), 164.308(a)(7)(i), 164.308(a)(7)(ii)(A), 164.310(a)(1), 164.310(a)(2)(i),
         164.310(a)(2)(ii), 164.310(a)(2)(iii), 164.310(b), 164.310(c), 164.310(d)(1), 164.310(d)(2)(iii)
nist     AC-3
ospp     FIA_UAU.1, FIA_AFL.1
pcidss4  8.3.4
os-srg   SRG-OS-000480-GPOS-00227
EOF

var_authselect_profile="sssd"

authselect current

if [ ${?} -ne 0 ] ; then
    authselect select "${var_authselect_profile}"

    if [ ${?} -ne 0 ] ; then
        if rpm --quiet --verify pam ; then
            authselect select --force "${var_authselect_profile}"
        else
            echo "authselect is not used but files from the 'pam' package have been altered, so the authselect configuration won't be forced." >&2
        fi
    fi
fi
