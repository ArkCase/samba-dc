#!/bin/bash
set -euo pipefail

cat <<-EOF
STIG Remediation script for:

cis        1.6.1
hipaa      164.308(a)(4)(i), 164.308(b)(1), 164.308(b)(3), 164.312(e)(1), 164.312(e)(2)(ii)
ism        1446
nerc-cip   CIP-003-8 R4.2, CIP-007-3 R5.1, CIP-007-3 R7.1
nist       AC-17(a), AC-17(2), CM-6(a), MA-4(6), SC-13, SC-12(2), SC-12(3)
ospp       FCS_COP.1(1), FCS_COP.1(2), FCS_COP.1(3), FCS_COP.1(4), FCS_CKM.1, FCS_CKM.2, FCS_TLSC_EXT.1
pcidss4    2.2.7
os-srg     SRG-OS-000396-GPOS-00176, SRG-OS-000393-GPOS-00173, SRG-OS-000394-GPOS-00174
stigref    SV-230223r928585_rule
EOF

set -euo pipefail

var_system_crypto_policy="DEFAULT:NO-SHA1"

stderr_of_call="$(update-crypto-policies --set "${var_system_crypto_policy}" 2>&1 > /dev/null)" && exit 0
rc=${?}
if [ ${rc} -eq 127 ] ; then
    echo "$stderr_of_call"
    echo "Make sure that the script is installed on the remediated system."
    echo "See output of the 'dnf provides update-crypto-policies' command"
    echo "to see what package to (re)install"
else
    echo "Error invoking the update-crypto-policies script (rc=${rc}): $stderr_of_call"
fi >&2
exit ${rc}
