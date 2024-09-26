#!/bin/bash
set -euo pipefail

cat <<-EOF
STIG Remediation script for:

cis       4.4.2.2
disa      CCI-000044
nist      AC-7 (a)
os-srg    SRG-OS-000021-GPOS-00005
stigref   SV-244534r743851_rule SV-244534r743851_rule
EOF

if [ -f /usr/bin/authselect ]; then
    if ! authselect check; then
        echo "authselect integrity check failed. Remediation aborted!
        This remediation could not be applied because an authselect profile was not selected or the selected profile is not intact.
        It is not recommended to manually edit the PAM files when authselect tool is available.
        In cases where the default authselect profile does not cover a specific demand, a custom authselect profile is recommended."
        exit 1
    fi
    authselect enable-feature with-faillock

    exec authselect apply-changes -b
fi

AUTH_FILES=("/etc/pam.d/system-auth" "/etc/pam.d/password-auth")
for pam_file in "${AUTH_FILES[@]}"
do
    if ! grep -qE '^\s*auth\s+required\s+pam_faillock\.so\s+(preauth silent|authfail).*$' "$pam_file" ; then
        sed -i --follow-symlinks '/^auth.*sufficient.*pam_unix\.so.*/i auth        required      pam_faillock.so preauth silent' "$pam_file"
        sed -i --follow-symlinks '/^auth.*required.*pam_deny\.so.*/i auth        required      pam_faillock.so authfail' "$pam_file"
        sed -i --follow-symlinks '/^account.*required.*pam_unix\.so.*/i account     required      pam_faillock.so' "$pam_file"
    fi
    sed -Ei 's/(auth.*)(\[default=die\])(.*pam_faillock\.so)/\1required     \3/g' "$pam_file"
done
