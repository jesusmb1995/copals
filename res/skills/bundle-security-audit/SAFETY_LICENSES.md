# SAFETY_LICENSES.md — License Compliance for Generated Bundles

This document tells an **AI agent** (or a human reviewer) how to scan a generated
`jberlanga-devtools` bundle for license problems, why **AGPL is strictly
prohibited** in most corporate/internal environments, and why you must **verify
the real license of each source** instead of blindly trusting the `LICENSE` file
shipped inside a package.

Scope: any pre-fetched third-party code that ends up under
`src/.config/nvim/lazy/`, `src/` vendored repos, or copied into the image.
The nvim pre-fetch gate lives in `user/repo-hooks/generate_nvim.lua` and is
enabled per config via `features.license_gate` (`warn` | `block`) on the `nvim`
repo entry.

---

## 1. Why AGPL (and network-copyleft) is strictly prohibited

- **The network clause is the killer.** Unlike GPL, AGPL's copyleft is triggered
  by **network use**, not just distribution: if a service *lets users interact
  with it over a network*, the complete corresponding source must be released
  under AGPL. This means a single AGPL dependency can force source disclosure of
  an entire service — far beyond the dependency itself. That blast radius is why
  AGPL is treated as a hard ban in corporate/internal contexts, even where plain
  GPL is tolerated.
- **GPL/LGPL are NOT in the same category.** GPL/LGPL permit commercial use and
  redistribution; they only add a source-disclosure obligation when you
  *distribute* the combined work. They are generally acceptable for internal /
  personal use and for externally distributed products as long as you comply
  with that obligation. Our gate therefore treats **GPL/LGPL as acceptable** and
  **AGPL as always flagged/blocked**.
- **Org-specific bans vary.** Some organizations additionally ban GPL/LGPL, or
  only permit a strict allowlist (MIT/Apache/BSD/ISC). Encode that by switching
  `features.license_gate` to `block` (fails generate) or by maintaining an
  allowlist. The gate's classification is the mechanism; the *policy* is set per
  config.

> Rule: **AGPL = block. GPL/LGPL = allowed (warn only) by default.** If you find
> AGPL in the bundle, remove it before the bundle is deployed to any environment
> that prohibits network-copyleft.

---

## 2. Always verify the TRUTH of the license — never trust the bundled file

The `LICENSE`/`COPYING` file that ships inside a package is **not authoritative
proof**. It can be:

- **Missing** — the repo forgot to include it, or the pre-fetch only grabbed a
  shallow checkout (this is why `nvim-clang-tidy-analysis` shows up as `unknown`).
- **Wrong / stale** — a repo re-licensed (e.g. nvim-tree.lua switched to GPLv3)
  but an old MIT `LICENSE` lingers, or a monorepo's root license doesn't apply to
  a subfolder you actually use.
- **Misleading** — some "LICENSE" files are actually proprietary EULAs, or the
  grant is buried in a README/package.json/`SPDX-License-Identifier` that
  contradicts the prose.
- **Substituted** — a malicious or careless fork can swap the license text.

**So the gate's file-scan is a first pass, not the verdict.** For any plugin the
scanner flags (`restrictive` or `unknown`), the AI MUST corroborate against the
**upstream source of truth**:

1. Resolve the plugin's canonical repo from `lazy-lock.json` (the `repo`/`url`
   + pinned `commit`).
2. Open the repo at that exact commit on the forge (GitHub/GitLab) and read its
   **real** license: the `LICENSE` file, the `SPDX-License-Identifier` in
   `package.json`/source headers, and the project's stated license.
3. If the bundled file disagrees with upstream, **trust upstream**, note the
   discrepancy, and re-classify.
4. If upstream also has no clear license, treat it as **proprietary by default**
   (`unknown` → must be reviewed/removed, never assumed OK).

The `license_text()` helper in `generate_nvim.lua` already falls back to
`git show HEAD:<license-blob>` and then the README — extend that habit: when in
doubt, go to the network source of truth, not the cached tree.

---

## 3. How an AI scans the generated bundle

### 3.1 Automated (what the gate does)

For each resolved plugin under `src/.config/nvim/lazy/<name>/`:

1. Collect license text: `LICENSE` / `LICENSE.md` / `LICENSE.txt` / `LICENCE` /
   `COPYING` / `UNLICENSE` at root, else the same via `git show HEAD:<blob>`,
   else a `license` section of `README.md`.
2. Classify by keyword matching (see `classify()` in `generate_nvim.lua`):
   - **AGPL** (`affero`, `agpl`) → `restrictive` (always).
   - **Forbidding** (`non-commercial`, `no commercial use`, `may not
     redistribute`, `all rights reserved`, `for personal use only`, ...) →
     `restrictive`.
   - **Permissive/copyleft-OK** (`permission is hereby granted`, `redistribut*`,
     `mit`, `bsd`, `apache`, `gpl`, `gnu general public`, `copyleft`, ...) →
     `permissive` (GPL/LGPL accepted).
   - **Empty / no license text** → `unknown`.

   > Keyword matching is intentionally conservative. "proprietary" is NOT a
   > restrictive marker — GPL/MIT texts mention it in their NO-WARRANTY sections
   > and would cause false positives.
3. `warn` mode → prints `WARN ... N plugin(s) lack a clear ... license: <list>`.
   `block` mode → `os.exit(1)` and refuses to generate.

### 3.2 Manual / AI verification pass (do this for every flagged plugin)

- Pull the pinned commit from `lazy-lock.json`.
- Confirm the license at that commit matches the bundle's classification.
- If `unknown`: go upstream; if upstream is genuinely unlicensed, **remove the
  plugin or get an explicit exception** — do not ship "no license".
- If `restrictive` and it is AGPL → **remove**, no exceptions.
- If `restrictive` and it is a non-commercial/proprietary license → **remove**
  (such licenses forbid commercial use, which is incompatible with most
  organizational deployment).

### 3.3 Commands

```sh
# list every pre-fetched plugin checkout
ls src/.config/nvim/lazy/

# show the pinned license source for one plugin
jq -r '.[] | select(. != null)' src/.config/nvim/lazy-lock.json | head   # (or open the json)
grep -rilE "affero|agpl" src/.config/nvim/lazy/*/LICENSE* 2>/dev/null     # quick AGPL sweep

# run the gate live (warn)
sh ./copals/copals.sh generate user config_gpersonal jberlanga-devtools -f
grep -i "license gate" <log>
```

---

## 4. Component license summary table (fill this in per bundle)

Keep this table current for every released bundle. `Verified` = cross-checked
against upstream at the pinned commit; `Bundled-only` = only the local file was
read (treat with suspicion).

| Component (repo@commit)        | Bundled LICENSE | Class      | Verified? | Notes |
|--------------------------------|-----------------|------------|-----------|-------|
| NvChad@`<commit>`              | GPL-3.0         | permissive | Bundled-only | GPL accepted; framework dep |
| lazy.nvim@`<commit>`           | MIT             | permissive | Bundled-only | |
| nvim-tree.lua@`<commit>`       | GPL-3.0         | permissive | Bundled-only | re-licensed from MIT; OK under GPL policy |
| nvim-dap-python@`<commit>`     | GPL-3.0         | permissive | Bundled-only | |
| diffview.nvim@`<commit>`       | MIT             | permissive | Bundled-only | |
| nvim-lint@`<commit>`           | GPL-3.0         | permissive | Bundled-only | |
| nvim-clang-tidy-analysis@`<c>` | **none**        | unknown    | **TODO**  | no LICENSE in checkout — verify upstream before shipping |
| `<other>`@`<commit>`           | `<license>`     | `<class>`  | `<...>`  | |

**Acceptable classes:** `permissive` (MIT/Apache/BSD/ISC/Unlicense/CC0/Zlib/WTFPL,
and GPL/LGPL copyleft).
**Must-fix classes:** `restrictive` when caused by **AGPL** or **non-commercial /
proprietary** terms; `unknown` when no license can be established upstream.

---

## 5. Checklist before deploying a bundle

- [ ] `license_gate` ran and reported 0 `restrictive` (AGPL/NC) and 0 unresolved `unknown`.
- [ ] Every `unknown` was verified upstream; unlicensed code was removed or excepted.
- [ ] No `affero`/`agpl` string anywhere under `src/.config/nvim/lazy/`.
- [ ] The component table above is filled in and signed off.
- [ ] GPL/LGPL components are noted as `restricted` per the target environment's
      policy (internal use typically OK; not for externally distributed products
      unless the source-disclosure obligation is met).
