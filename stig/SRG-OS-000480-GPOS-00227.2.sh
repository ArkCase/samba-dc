#!/bin/bash
set -euo pipefail

cat <<-EOF
STIG Remediation script for:

cis             4.5.2.3
cis-csc         1, 12, 13, 14, 15, 16, 18, 3, 5, 7, 8
cobit5          DSS01.03, DSS03.05, DSS05.04, DSS05.05, DSS05.07, DSS06.03
disa            CCI-000366
isa-62443-2009  4.3.3.2.2, 4.3.3.5.1, 4.3.3.5.2, 4.3.3.7.2, 4.3.3.7.3, 4.3.3.7.4
isa-62443-2013  SR 1.1, SR 1.2, SR 1.3, SR 1.4, SR 1.5, SR 1.7, SR 1.8, SR 1.9, SR 2.1, SR 6.2
ism             1491
iso27001-2013   A.12.4.1, A.12.4.3, A.6.1.2, A.7.1.1, A.9.1.2, A.9.2.1, A.9.2.2, A.9.2.3,
                A.9.2.4, A.9.2.6, A.9.3.1, A.9.4.1, A.9.4.2, A.9.4.3, A.9.4.4, A.9.4.5
nist            AC-6, CM-6(a), CM-6(b), CM-6.1(iv)
nist-csf        DE.CM-1, DE.CM-3, PR.AC-1, PR.AC-4, PR.AC-6
pcidss4         8.2.2
os-srg          SRG-OS-000480-GPOS-00227
EOF

readarray -t systemaccounts < <(awk -F: '($3 < 1000 && $3 != root \
  && $7 != "\/sbin\/shutdown" && $7 != "\/sbin\/halt" && $7 != "\/bin\/sync") \
  { print $1 }' /etc/passwd)

for systemaccount in "${systemaccounts[@]}"; do
	usermod -s /sbin/nologin "$systemaccount"
done
