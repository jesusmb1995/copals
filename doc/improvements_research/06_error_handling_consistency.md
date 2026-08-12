# 06 — Error Handling & Status Propagation

## Problem Statement

Amber offers several ways to handle command failure: `?` propagation,
`failed { }` recovery blocks, `trust` (discard the status), `status()` (read
the last exit code), `succeeded { }`, and `fail N`. Copals uses **all of them**
without a documented convention, and several patterns silently swallow errors.
This makes failure paths hard to audit — a significant concern for a tool whose
core value proposition is producing an *auditable* `install.sh`.

Concretely:

1. **No exit-code scheme.** Almost everything `fail 1`s, but a few sites use
   `fail 2`; the meanings are undocumented and there is no mapping for callers.
2. **`trust` is overused** (88 sites), discarding the command status entirely —
   and the codebase itself flags this
   (`src/shlib/test/screenshot.ab:63`: *"dont force infallible on these
   functions ... makes no sense to use trust everywhere"*).
3. **Error swallowing is common** (`failed { return null }`, empty
   `failed {}`, `failed { return "" }`), often without logging.
4. **`echo_error` vs `fail` do different things.** `echo_error(msg)` prints
   red but **does not exit** unless given a positive exit code, so a bare
   `echo_error` is frequently mistaken for a fatal call.

## Evidence

### Construct usage across `src/**/*.ab`

| Construct | Occurrences | Meaning |
|---|---|---|
| `?` (propagate) | 542 | primary error path — abort on failure |
| `echo_error` | 101 | prints red; exits **only** if 2nd arg > 0 |
| `trust $...$` | 88 | runs command, **discards** status, returns stdout |
| `failed { }` | 85 | recovery branch on failure |
| `fail N` | 34 | explicit fatal exit |
| `status()` | 3 | read last exit code inside `failed` |

The mix is not wrong per se — each construct has a use — but the *ratios* show
no guiding rule: `trust` (silent) is used nearly as often as the explicit
`failed` (auditable) path.

### Error swallowing — concrete sites

Silent recovery that returns a sentinel without logging:

```amber
// src/gen/generate.ab:106  — mv failure becomes a silent null
mv("{meta_json_path}.tmp", "{meta_json_path}") failed { return null }

// src/shlib/fetch.ab:19  — download failure swallowed
download_to(url, target) failed { return null }

// src/shlib/install/brew.ab:57-58  — rm/ln failures swallowed
$ rm -rf {locks_dir} $ failed { return null }
$ ln -sf /tmp/brew-locks {locks_dir} $ failed { return null }

// src/shlib/install/ask.ab:4  — missing env defaults silently to "true"
const ask = env_var_get("COPALS_ASK") failed { return true }
```

And the most aggressive — **empty** recovery that drops the error entirely:

```amber
// src/shlib/git.ab:38-39
$ git -C "{repo}" config user.email "test@example.com" $ failed {}
$ git -C "{repo}" config user.name "Test User" $ failed {}
```

Each of these may be *intentional*, but none records that a failure happened, so
a downstream null/empty value has no provenance when debugging.

### The self-flagged `trust` overuse

`src/shlib/test/screenshot.ab:63`:
```
// TODO REVIEW: dont force infallible on these functions, the user can wrap
// them on failed {} if needed buut makes no sense to use trust everywhere
```
This is a standing acknowledgement that `trust` is being used as a convenience
to avoid propagating, at the cost of observability.

### Undocumented exit codes

Distribution of `fail N`:

| Code | Sites |
|---|---|
| `fail 1` | 32 |
| `fail 2` | 2 (`src/gen/generate.ab` glob-too-many, `src/shlib/fs.ab` unique-match-too-many) |

Only `fail 1` (generic) and `fail 2` (ambiguous match) appear, and the
distinction is not documented anywhere. `generate.ab` even reads it back via
`status()` in one place (`const exit_code = status()` at the glob site) but
not consistently — most callers cannot distinguish "no match" from "too many".

### `echo_error` is not fatal by default

From the compiled `src/copals.sh:754`, `echo_error(message, exit_code)` only
calls `exit` when `exit_code > 0`:
```bash
if [ "$(( exit_code_323 > 0 ))" != 0 ]; then exit "${exit_code_323}"; fi
```
So `echo_error("config not found")` prints and **continues**. Several call-sites
follow it with an explicit `fail 1`, but not all — the bare form invites bugs
where an "error" is actually a warning.

## Proposed Changes

Each item: Effort (S/M/L), Risk (Low/Med/High).

### 1. Document the error-handling convention — Effort S, Risk Low

Add a section to a developer doc (e.g. `doc/contributing.md` or `AGENTS.md`,
see doc 04) defining the canonical mapping:

| Situation | Use |
|---|---|
| Cannot continue, propagate to caller | `?` |
| Recoverable, want to branch | `failed { }` and **always** log/return a meaningful value |
| Read the exit code inside `failed` | `status()` |
| Truly optional command (best-effort) | `trust` — but justify in a comment |
| Fatal, top-level | `fail <code>` |

State the rule: **`trust` and empty `failed {}` require a justifying
comment.** Pure documentation; no code risk.

### 2. Define an exit-code scheme — Effort S, Risk Low

Adopt a small, documented set (e.g. `1` generic, `2` usage/arg,
`3` config-not-found, `4` ambiguous-match, `5` network/fetch) and replace the
ad-hoc `fail 1`/`fail 2` at the special sites. Update `print_help`/docs.
Risk Low if done as a rename with the scheme table; audit call-sites so no two
errors collapse to a code that a caller distinguishes.

### 3. Make swallowed errors observable — Effort M, Risk Low

For every `failed { return <sentinel> }` and empty `failed {}`, add a
`echo_warning(...)` (or a debug log) before returning, so failures leave a
trace. This is the highest-value observability change and aligns with the
"auditable" value proposition. Risk Low (behaviour unchanged, only output
added), Effort M because there are ~85 `failed` sites to triage.

### 4. Replace unjustified `trust` with `?` or `failed` — Effort M, Risk Med

Audit the 88 `trust` sites; convert each to `?` (propagate) or an explicit
`failed { }` unless a comment justifies the discard. Start with the
non-`test/` modules (the test layer's `trust` is lower-stakes). Risk Med
because some `trust` sites may rely on the silent pass-through for control
flow; convert incrementally behind the test suite (doc 04).

### 5. Clarify `echo_error` vs `fail` — Effort S, Risk Low

Either (a) introduce `echo_fatal(msg, code)` that always exits, reserving
`echo_error` for non-fatal warnings, or (b) audit `echo_error` call-sites and
add the missing `fail` where fatality was intended. Removes the "prints red
but keeps going" footgun. Risk Low.

## Recommendation

Sequence: **1 → 2 → 5 → 3 → 4.**

- **1** and **2** first: they codify the convention and code scheme that the
  later changes enforce — cheap and they make review of 3/4 mechanical.
- **5** next: small, fixes a real footgun (`echo_error` non-fatality).
- **3** (log swallowed errors) is the biggest observability win for the least
  behavioural risk; do it before 4.
- **4** (de-`trust`) is the largest and riskiest; sequence it after the test
  coverage improvements in doc 04 so conversions are gated by tests.

## Out of Scope / Risks

- **Amber's own semantics.** The `?`/`failed`/`trust`/`status` model is fixed
  by the language; this doc does not propose changing how Amber propagates,
  only how Copals chooses among the options.
- **Behavioural equivalence.** Changes 3 (logging) and 5 are output-only. Change
  4 (`trust` → `?`) **does** alter control flow at sites that depended on the
  silent pass-through, so it must be incremental and test-gated; a blanket
  conversion is explicitly out of scope.
- **Exit-code stability for generated `install.sh`.** If the scheme (change 2)
  is exposed to consumers of the generated installer, changing codes is a
  breaking change for scripts that branch on `$?`; scope the scheme to the
  `copals` CLI and document the installer's codes separately.
- **Performance/logging volume.** Change 3 adds output on recovery paths; in
  parallel generation (`run_parallel`) this can interleave. Use the existing
  `log_genstep` style or a buffered logger rather than raw `echo` to keep
  output coherent.
- **Interaction with doc 03/05.** Hook authors and package-manager backends
  must follow the convention defined here; land the convention (1/2) before the
  hook-unification (doc 03) and pkg-abstraction (doc 05) work so new code is
  written to the standard.
