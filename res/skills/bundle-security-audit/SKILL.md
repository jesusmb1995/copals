---
name: bundle-security-audit
description: Audit a generated copals bundle before deployment — check third-party licenses and scan for malicious or non-auditable code. Use when reviewing a bundle for internal corporate/enterprise developer use.
---

# bundle-security-audit

Audit a **generated copals bundle** (the self-contained `install.sh` plus its
pre-fetched sources under `src/`) before it is deployed. The bundle is meant to
be **suitable for internal use by developers in a corporate/enterprise
environment**, so the audit has two independent goals:

1. **Licenses** — no forbidden licenses ship in the bundle. AGPL and
   network-copyleft are blocked; non-commercial / proprietary terms are blocked;
   GPL/LGPL are acceptable for internal use; every `unknown` must be resolved.
   Never trust a bundled `LICENSE` file — verify the upstream truth at the pinned
   commit. Full policy: `@SAFETY_LICENSES.md`.
2. **Code safety** — no malicious, obfuscated, or non-auditable code, and **no
   opaque binaries**. Everything that runs at install time must be plain,
   reviewable source. Full policy: `@SAFETY_CODE.md`.

Both `SAFETY_LICENSES.md` and `SAFETY_CODE.md` are bundled next to this
`SKILL.md`. Resolve their absolute paths and read them in full before judging a
bundle.

## How to run the audit

1. Read `@SAFETY_LICENSES.md` and `@SAFETY_CODE.md`.
2. **License pass** — for every pre-fetched dependency, classify its license and
   corroborate `restrictive`/`unknown` findings against the upstream repo at the
   pinned commit. AGPL / non-commercial / unresolved-unknown = must-fix.
3. **Code pass** — scan `install.sh`, all `repo-hooks`, and every pre-fetched
   source tree for binaries, obfuscation, and untrusted network/exec at install
   time (`curl|sh`, `eval`, opaque archives, credential exfiltration).
4. **Verdict** — the bundle is deployable only when both passes are clean: zero
   forbidden licenses, zero unresolved `unknown`, zero binaries, and no
   suspicious code paths. Report every finding; do not silently pass.

## Report format

Emit a short summary plus, per finding: the component (`repo@commit` or file
path), which check failed (license class or code issue), evidence, and the
required action (remove / verify upstream / get exception). Keep the license
component table from `@SAFETY_LICENSES.md` current for the audited bundle.

This skill performs **analysis only** — it does not modify the bundle.
