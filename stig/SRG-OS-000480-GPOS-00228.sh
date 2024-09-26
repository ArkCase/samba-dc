#!/bin/bash
set -euo pipefail

cat <<-EOF
STIG Remediation script for:

anssi           R36
cis             4.5.3.3
cis-csc         18
cobit5          APO13.01, BAI03.01, BAI03.02, BAI03.03
disa            CCI-000366
isa-62443-2009  4.3.4.3.3
iso27001-2013   A.14.1.1, A.14.2.1, A.14.2.5, A.6.1.5
nerc-cip        CIP-003-8 R5.1.1, CIP-003-8 R5.3, CIP-004-6 R2.3, CIP-007-3 R2.1, CIP-007-3 R2.2,
                CIP-007-3 R2.3, CIP-007-3 R5.1, CIP-007-3 R5.1.1, CIP-007-3 R5.1.2
nist            AC-6(1), CM-6(a)
nist-csf        PR.IP-2
os-srg          SRG-OS-000480-GPOS-00228, SRG-OS-000480-GPOS-00227
stigref         SV-230385r792902_rule
EOF

var_accounts_user_umask="027"


readarray -t profile_files < <(find /etc/profile.d/ -type f -name "*.sh" -or -name "sh.local")

for file in "${profile_files[@]}" /etc/profile; do
    grep -qE "^[^#]*umask" "${file}" && sed -i -E "s/^(\s*umask\s*)[0-7]+/\1${var_accounts_user_umask}/g" "${file}"
done

if ! grep -qrE "^[^#]*umask" /etc/profile*; then
    echo "umask ${var_accounts_user_umask}" >> /etc/profile
fi
