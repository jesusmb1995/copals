#!/bin/sh
# copals-audit: scan a directory with opengrep + trufflehog + trivy + clamav.
#
# Exits non-zero if ANY tool reports findings (opengrep SAST hit, trufflehog
# verified secret, trivy CVE, clamav infected file) or if any required tool is
# missing (a missing tool would make the audit a false pass, so it is treated
# as failure).
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
# opengrep installs its symlink into ~/.local/bin (not via brew), so make sure
# that is on PATH for both the host and the security container.
[ -d "${HOME}/.local/bin" ] && PATH="${HOME}/.local/bin:${PATH}"
export PATH

# Fail hard if any required tool is missing.
missing=0
for t in opengrep trufflehog trivy clamscan; do
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

printf '== opengrep (SAST) ==\n'
# opengrep is the community-maintained open-source fork of the semgrep engine
# (LGPL). `--config=auto` pulls its OSS rule pack, which resolves to the same
# community rules semgrep's CE would run, so this is the single SAST pass.
# --no-git-ignore is required because the generated bundle is git-ignored
# (jberlanga-devtools/ in .gitignore); without it opengrep scans 0 files.
# --error: exit 1 when findings are reported.
opengrep scan --error --config=auto --no-git-ignore "$dir" || rc=$?

printf '== trufflehog (secret scan) ==\n'
# --fail: exit 183 when verified secrets are found.
# Positional path arg (trufflehog 3.95+ deprecated --directory).
trufflehog filesystem "$dir" --fail || rc=$?

printf '== trivy (SCA) ==\n'
# Software Composition Analysis: open-source CVE scan of dependency manifests
# (npm/pip/gem/cargo/go/...). --scanners vuln restricts to dependency CVEs
# (secret/misconfig layers are left to trufflehog/opengrep above).
# --ignore-unfixed skips CVEs with no published fix (noise reduction).
# --exit-code 1 fails the gate on any fixable finding. We intentionally scan the
# full tree INCLUDING the vendored nvim plugin tree (lazy/): upstream plugins
# sometimes bundle vulnerable dep manifests (e.g. vim-bookmarks' Gemfile.lock
# pins vulnerable addressable/faraday/thor). The installer strips dev-only
# manifests (see generate_nvim_postrender.lua), so this catches real risk rather
# than hiding it behind a skip.
trivy fs --scanners vuln --exit-code 1 --ignore-unfixed "$dir" || rc=$?

printf '== clamav (AV) ==\n'
# ClamAV assumes a system service (root + a dedicated `clamav` user). On a
# user-mode host the system DB/log dirs (/var/lib/clamav, /var/log/clamav) are
# owned by the clamav user and not writable, and a system freshclam.conf can
# shadow brew's. Use a self-contained, user-owned DB dir + generated freshclam
# conf so the scan is independent of system package state. Override the dir via
# COPALS_CLAM_DB.
clam_db_dir="${COPALS_CLAM_DB:-$HOME/.cache/copals/clamav-db}"
mkdir -p "$clam_db_dir"
clam_conf="$clam_db_dir/freshclam.conf"
if [ ! -f "$clam_conf" ]; then
    cat > "$clam_conf" <<EOF
DatabaseDirectory $clam_db_dir
UpdateLogFile $clam_db_dir/freshclam.log
DatabaseMirror database.clamav.net
EOF
fi
# Refresh the signature DB. If the DB is already present (e.g. cached from a
# prior run, or baked into the image) a failed/blocked refresh is non-fatal;
# but if the DB is MISSING, a failed update would make clamscan a false pass,
# so that is a hard failure.
has_db=0
for _ext in cvd cld; do
    if ls "$clam_db_dir"/*."$_ext" >/dev/null 2>&1; then has_db=1; break; fi
done
if [ "$has_db" -eq 0 ]; then
    if ! freshclam --config-file="$clam_conf" >/dev/null; then
        printf 'copals-audit: freshclam failed and no signature DB present\n' >&2
        rc=2
    fi
else
    freshclam --config-file="$clam_conf" --quiet >/dev/null 2>&1 || true
fi
clamscan -r --infected --database="$clam_db_dir" "$dir" || rc=$?

if [ "$rc" -ne 0 ]; then
    printf 'copals-audit: FAIL — issues detected in %s (rc=%d)\n' "$dir" "$rc" >&2
else
    printf 'copals-audit: OK — no issues in %s\n' "$dir"
fi
exit "$rc"
