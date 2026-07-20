# SAFETY_CODE.md — Malicious / Non-Auditable Code Review for Generated Bundles

This document tells an **AI agent** (or a human reviewer) how to scan a generated
`jberlanga-devtools` bundle for **malicious, obfuscated, or non-auditable code**
before it is deployed. It is the code-safety counterpart to
`SAFETY_LICENSES.md` (license compliance).

Scope: the self-contained `install.sh`, all `repo-hooks/` scripts, and every
pre-fetched third-party source tree that ends up under `src/` or is copied into
the image. The whole point of copals' pre-fetch/audit pipeline is that the
output is a **single, plain-text, auditable installer** — so anything that
undermines that auditability is a finding.

---

## 1. Core principle: everything must be readable source

A bundle is acceptable for internal developer use only if a reviewer can read
and understand **everything that will execute** at install time. Two things break
that guarantee and are therefore treated as hard findings:

- **Opaque binaries** — code you cannot review (compiled executables, blobs).
- **Obfuscation / remote fetch** — code that hides its behavior or defers it to
  something pulled from the network at install time.

> Rule: **No binaries, no obfuscation, no untrusted install-time network/exec.**
> If behavior cannot be reviewed from the bundle's plain text, it is a finding.

---

## 2. No binaries in the auditable surface

The installer and its pre-fetched sources must be plain text. Flag any:

- **Executable object files** — ELF, Mach-O, PE/`.exe`/`.dll`, `.so`, `.dylib`,
  `.a`, `.o`, `.class`, `.jar`, `.wasm`.
- **Opaque archives shipped to be extracted-and-run** — `.tar.*`, `.zip`,
  `.deb`, `.rpm`, `.AppImage`, `.dmg` whose contents are not themselves audited.
- **Encoded blobs in scripts** — large base64/hex payloads decoded then
  executed or written to disk.
- **Minified / generated code** treated as source (single-line multi-KB JS,
  etc.) with no readable original.

Legitimate exceptions (fonts, images, icons, sample data) are fine **only** when
they are pure data, never executed, and clearly identified. When in doubt, treat
a binary as a finding and require it be built from source at deploy time or
removed.

### Quick binary sweep

```sh
# any non-text file under the pre-fetched sources
find src -type f -exec sh -c 'file "$1" | grep -qiE "ELF|Mach-O|PE32|archive|executable" && echo "$1"' _ {} \;

# encoded blob decode-and-run patterns
grep -rnE "base64 -d|xxd -r|openssl enc -d" src install.sh repo-hooks 2>/dev/null
```

---

## 3. No malicious or obfuscated behavior

Read `install.sh`, every `repo-hooks/*` script, and any script the sources run.
Flag:

- **Untrusted install-time network + exec** — `curl ... | sh`, `wget ... | bash`,
  `eval "$(curl ...)"`. Sources should already be pre-fetched; pulling and
  running new code at deploy time defeats the audit.
- **Dynamic evaluation of opaque input** — `eval`, `source`/`.` of a downloaded
  or decoded string, `python -c`/`node -e` with encoded payloads.
- **Credential / data exfiltration** — reads of `~/.ssh`, `~/.aws`, `.netrc`,
  env tokens, browser profiles, keyrings, followed by any network send.
- **Persistence / privilege abuse** — unexpected `sudo`, setuid, cron/systemd
  units, shell-rc edits, or writes outside the declared install targets.
- **Destructive operations** — unscoped `rm -rf`, `dd`, disk/partition writes.
- **Obfuscation** — hex/octal/`$'\xNN'` command building, char-code assembly,
  heavily indirected variable expansion whose only purpose is to hide intent.

### Quick behavior sweep

```sh
grep -rnE "curl[^|]*\|[[:space:]]*(sh|bash)|wget[^|]*\|[[:space:]]*(sh|bash)" install.sh repo-hooks src 2>/dev/null
grep -rnE "\beval\b|\bsource\b .*(curl|wget|http)" install.sh repo-hooks src 2>/dev/null
grep -rnE "\.ssh|\.aws|\.netrc|id_rsa|AWS_SECRET|_TOKEN" install.sh repo-hooks src 2>/dev/null
grep -rnE "rm -rf[[:space:]]+/|dd if=|mkfs|crontab|systemctl enable" install.sh repo-hooks src 2>/dev/null
```

Any hit is a lead, not an automatic verdict — read the surrounding code and judge
intent. Prefer pre-fetch over deploy-time fetch; prefer plain source over
anything decoded or downloaded.

---

## 4. Checklist before deploying a bundle

- [ ] No ELF/Mach-O/PE/`.so`/`.jar`/`.wasm` or other opaque binaries under `src/`
      (or each is justified pure data, never executed).
- [ ] No encoded blobs that are decoded and executed/written.
- [ ] No `curl|sh` / `wget|bash` / `eval "$(curl ...)"` at install time — all
      sources are pre-fetched and reviewable.
- [ ] No credential/keyring/token reads paired with network sends.
- [ ] No unexpected privilege escalation, persistence, or writes outside declared
      install targets.
- [ ] No destructive or obfuscated commands.
- [ ] Every install-time script was read and understood, not skimmed.
