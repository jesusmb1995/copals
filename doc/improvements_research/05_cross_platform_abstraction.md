# 05 — Cross-Platform & Package-Manager Abstraction

## Problem Statement

The README states Copals "is tuned heavily for debian:testing" and lists
"Multi-OS & Package Manager Support" under Future Work. In practice the
codebase bakes Debian/macOS assumptions directly into logic:

1. **No package-manager abstraction.** `src/shlib/pkg.ab` exposes
   `apt_install`, `brew_install`, `npm_install` as separate functions and
   *hardcodes apt as the fallback* (`npm_install` calls `apt_install("npm")`
   if `npm` is missing — `pkg.ab:18-23`). There is no `pkg_install(name)` that
   selects a backend by host.
2. **Privilege escalation is inconsistent.** The compiled entry prologue
   detects `sudo` *or* `doas` (`src/copals.sh:4`), but the reusable
   `sudo_cmd` helper (`src/shlib/sudo.ab`) only knows about `sudo` and
   **silently drops privileges** when sudo is absent, instead of using doas or
   failing. Two different privilege strategies coexist.
3. **Hardcoded distro-specific paths.** `_brew_fix_lock_dir`
   (`src/shlib/pkg.ab:25-41`) hardcodes the Linuxbrew path
   `/home/linuxbrew/.linuxbrew/...`, which differs on macOS.
4. **OS detection exists but is unused by the install layer.** `src/shlib/os.ab`
   provides `is_macos()`/`is_linux()` via `uname`, yet `pkg.ab` never consults
   it.

This makes "deploy to Alpine/Arch/macOS" (a stated goal) require per-hook
rewrites instead of a backend swap.

## Evidence

### apt is the implicit default

`src/shlib/pkg.ab`:
```amber
pub fun apt_install(package: Text): Null? {
    sudo_cmd("apt-get install -y --no-install-recommends {package}", ["DEBIAN_FRONTEND=noninteractive"])?
}
pub fun npm_install(package: Text): Null? {
    if not is_command("npm") {
        apt_install("npm")        // hardcoded apt fallback
    }
    sudo_cmd("npm install -g {package}")?
}
```

`apt`/`apt-get`/`dpkg` appear in 11 source files
(`src/shlib/install/apt.ab`, `deb.ab`, `npm.ab`, `pkg.ab`, all of
`src/container/*.ab`, `copals.ab`). `brew`/`dnf`/`pacman`/`apk` appear only in
`brew.ab` and a couple of container files — there is no parity.

### Privilege escalation: two strategies, one of them lossy

Entry prologue (`src/copals.sh:4`, compiled from the amber entry):
```bash
[ "$EUID" -ne 0 ] && { { command -v sudo >/dev/null 2>&1 && __sudo=sudo; } \
  || { command -v doas >/dev/null 2>&1 && __sudo=doas; }; }
```
This correctly prefers `sudo` then `doas`.

But the reusable helper ignores doas entirely and falls back to **no
privilege**:
```amber
// src/shlib/sudo.ab
pub fun sudo_cmd(cmd: Text, envvar: [Text] = []): Null? {
    if has_cmd("sudo") {
        $ sudo {envvar} {cmd} $ ?
    } else {
        $ env {envvar} {cmd} $ ?     // silent privilege drop — no doas, no error
    }
}
```
On a doas-only host (common on OpenBSD/some Arch setups), `sudo_cmd` runs the
command unprivileged, which either fails opaquely or silently mis-installs.

### Hardcoded Linuxbrew path

`src/shlib/pkg.ab:25-41`:
```amber
fun _brew_fix_lock_dir(): Null? {
    const locks_dir = "/home/linuxbrew/.linuxbrew/var/homebrew/locks"
    ...
}
```
This path is correct only for Linuxbrew; on macOS Homebrew uses
`/opt/homebrew/...` (Apple Silicon) or `/usr/local/...` (Intel). The function
runs unconditionally inside `brew_install`.

### OS detection present but disconnected

`src/shlib/os.ab` provides exactly the primitive needed (`is_macos`,
`is_linux`, `current_os`), but `rg "is_macos|is_linux|current_os" src/shlib/pkg.ab src/shlib/install/*.ab` shows the install layer does not call them. The
abstraction's building block exists; it is simply not wired in.

### Container images are Debian-centric

| File | Base |
|---|---|
| `Dockerfile` | `alpine:${ALPINE_VERSION}` (build env) |
| `res/security.Dockerfile` | `debian:bookworm-slim` (hardcoded) |
| `res/*_base.Dockerfile`, `res/deploy_*.Dockerfile` | `${BASE}` (defaults to a debian target per README) |

The build toolchain runs on Alpine, but the *deploy/test* targets assume Debian
apt semantics in their scripts.

## Proposed Changes

Each item: Effort (S/M/L), Risk (Low/Med/High).

### 1. A package-manager abstraction — Effort M, Risk Med

Introduce a `pkg_install(name)` (and `pkg_install_many`) that selects a backend
by host capability, falling back through a preference list:

```amber
// src/shlib/pkg.ab (proposed shape)
pub fun pkg_install(package: Text): Null? {
    if has_cmd("apt-get")      { apt_install(package) }
    else if has_cmd("brew")    { brew_install_pkg(package) }
    else if has_cmd("pacman")  { pacman_install(package) }
    else if has_cmd("apk")     { apk_install(package) }
    else if has_cmd("dnf")     { dnf_install(package) }
    else { echo_error("no supported package manager for {package}"); fail 1 }
}
```

Keep the existing `apt_install`/`brew_install`/`npm_install` as the per-backend
implementations; add the missing backends (`apk`, `pacman`, `dnf`) and a
thin registry. Existing hooks that call `apt_install` directly keep working;
new hooks call `pkg_install`. Risk Med: backends must agree on flags
(`--no-install-recommends`, `-y`, `--noconfirm`); add a per-backend test fixture.

### 2. Fix `sudo_cmd` to honour doas and fail loudly — Effort S, Risk Low

Align the helper with the entry prologue: prefer `sudo`, then `doas`, then
**fail** rather than silently dropping privileges:

```amber
pub fn privileged_cmd(cmd, envvar = []): Null? {
    if has_cmd("sudo")      { $ sudo {envvar} {cmd} $ ? }
    else if has_cmd("doas") { $ doas {envvar} {cmd} $ ? }
    else if is_root()       { $ env {envvar} {cmd} $ ? }
    else { echo_error("need sudo or doas for: {cmd}"); fail 1 }
}
```

Risk Low: the only behaviour change is that doas-only hosts now work and
unprivileged installs fail fast instead of silently. Gate with the existing
install tests; keep `sudo_cmd` as a thin alias for compatibility.

### 3. Use `os.ab` in the install layer — Effort S, Risk Low

Route distro/macOS-specific behaviour through `is_macos()`/`is_linux()`. Concretely, make `_brew_fix_lock_dir` conditional on `is_linux()` (skip or use the
macOS path otherwise), and let `pkg_install` prefer `brew` on macOS. Risk Low:
the primitives already exist and are tested (`os.ab` has no test — add one as
part of doc 04).

### 4. De-hardcode the vendor/install path — Effort S/M, Risk Low

`/usr/lib/copals/vendor` (`src/shlib/vendor.ab:14`) and the linuxbrew path are
fine inside the Debian container but assume FHS. Parameterise via a config/env
override (e.g. `COPALS_VENDOR_DIR`) with the current value as default, so
non-Debian installs can point elsewhere. Risk Low: additive override, default
unchanged.

### 5. Multi-distro container test matrix — Effort M, Risk Med

Add Alpine/Arch/macOS targets to `res/` Dockerfiles and a matrixed integration
test (`test/integration/`) that runs `pkg_install` and a representative install
hook on each. This makes the Future Work goal measurable. Risk Med: container
images and CI time grow; scope to one extra distro (Alpine) first since the
build env already uses it.

## Recommendation

Sequence: **2 → 3 → 1 → 4 → 5.**

- **2** (fix `sudo_cmd`/doas) first: it is a latent correctness bug on doas
  hosts, Size S, and a prerequisite for any non-Debian target.
- **3** wires in the existing `os.ab` primitives — cheap, unblocks 1.
- **1** (pkg abstraction) is the core deliverable; land after 2 and 3 so its
  backends have correct privilege and OS routing.
- **4** removes the remaining hardcoded paths.
- **5** (test matrix) proves the abstraction end-to-end; expand one distro at a
  time.

## Out of Scope / Risks

- **Full macOS GUI support** (Homebrew casks, notarization, launchd) is not
  covered; this doc targets the package-manager and privilege layers that are
  prerequisites for any macOS work.
- **Backend behavioural parity.** `apt --no-install-recommends` has no exact
  equivalent in `pacman`/`apk`; the abstraction must define "install this
  package" minimally and document backend-specific flags rather than promise
  identical dependency resolution.
- **Container image sprawl.** Change 5 multiplies the image/CI surface; keep
  the default target Debian and treat others as opt-in to avoid slowing the
  common path.
- **Privilege model on read-only/rootless systems.** `privileged_cmd` failing
  loudly (change 2) is correct for installs but could break hooks that
  intentionally run unprivileged; expose an explicit `unprivileged_cmd` for
  those cases so the default remains safe.
- **Interaction with doc 03.** Install hooks (doc 03) are compiled into
  `install.sh` and call these helpers at deploy time, so the package-manager
  abstraction must remain stable across the generate/deploy boundary.
