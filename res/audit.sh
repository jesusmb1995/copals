#!/bin/sh
# copals-audit: scan a directory with semgrep + trufflehog + clamav.
#
# Exits non-zero if ANY tool reports findings (semgrep hit, trufflehog verified
# secret, clamav infected file) or if any required tool is missing (a missing
# tool would make the audit a false pass, so it is treated as failure).
#
# Baked into the copals:security image (ENTRYPOINT) and reusable on the host
# after `install.sh extensions` installs the same tools via brew.
set -u

dir="${1:-}"
if [ -z "$dir" ]; then
    printf 'usage: copals-audit <dir>\n' >&2
    exit 2
fi
if [ ! -d "$dir" ]; then
    printf 'copals-audit: not a directory: %s\n' "$dir" >&2
    exit 2
fi

# Put brew-installed tools on PATH (Linuxbrew in the container, /opt/homebrew or
# /usr/local on the host). No-op if brew is already on PATH.
for _b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$_b" ] && eval "$("$_b" shellenv)" 2>/dev/null && break
done

# Fail hard if any required tool is missing.
missing=0
for t in semgrep trufflehog clamscan; do
    if ! command -v "$t" >/dev/null 2>&1; then
        printf 'copals-audit: required tool missing: %s\n' "$t" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    printf 'copals-audit: install extensions first (install.sh extensions)\n' >&2
    exit 2
fi

rc=0

printf '== semgrep ==\n'
# --error: exit 1 when findings are reported (not just on scan errors).
semgrep scan --error --config=auto "$dir" || rc=$?

printf '== trufflehog ==\n'
# --fail: exit 183 when verified secrets are found.
trufflehog filesystem --directory="$dir" --fail || rc=$?

printf '== clamav ==\n'
# Refresh the signature DB. If the DB is already present (e.g. baked into the
# image) a failed/blocked refresh is non-fatal; but if the DB is MISSING, a
# failed update would make clamscan a false pass, so that is a hard failure.
clam_db_dir="$(freshclam --help 2>/dev/null | grep -oiE '/[^ ]*clamav' | head -1)"
[ -z "$clam_db_dir" ] && clam_db_dir="/home/linuxbrew/.linuxbrew/var/lib/clamav"
has_db=0
for _ext in cvd cld; do
    if ls "$clam_db_dir"/*."$_ext" >/dev/null 2>&1; then has_db=1; break; fi
done
if [ "$has_db" -eq 0 ]; then
    if ! freshclam --quiet; then
        printf 'copals-audit: freshclam failed and no signature DB present\n' >&2
        rc=2
    fi
else
    freshclam --quiet 2>/dev/null || true
fi
clamscan -r --infected "$dir" || rc=$?

if [ "$rc" -ne 0 ]; then
    printf 'copals-audit: FAIL — issues detected in %s (rc=%d)\n' "$dir" "$rc" >&2
else
    printf 'copals-audit: OK — no issues in %s\n' "$dir"
fi
exit "$rc"
