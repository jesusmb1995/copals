# 04 — Testing Infrastructure & Coverage

## Problem Statement

Copals ships a multi-layer test harness (`test/test.ab` dispatching to
`check`/`lib`/`smoke`/`integration`/`pipeline`), but **unit coverage is thin
and unevenly distributed**, the `gen/` pipeline that produces the auditable
`install.sh` has **no unit tests**, and the project ships **no `AGENTS.md`**
documenting how to run tests. The result is that the most logic-heavy, security-
relevant code (generation, post-processing, JSON config, the install hooks) is
exercised only by slow end-to-end container tests — if at all — while fast unit
tests protect only the leaf `shlib` utilities.

## Evidence

### Coverage by the numbers

| Metric | Value |
|---|---|
| Amber source files (`src/**/*.ab`) | 105 |
| Co-located unit-test files (`*.test.ab`) | 29 |
| Source files **without** a co-located unit test | 76 (~72%) |

### Untested logic modules (not just entry points)

Of the 76 untested files, many are pure logic (not I/O-bound launchers) and
should have unit tests:

- **Entire `src/gen/` pipeline is unit-untested:** `generate.ab`,
  `postprocess.ab`, `json_config.ab`, `process-repo.ab`, `audit.ab`,
  `compile-job.ab`, `render-job.ab`, `file-job.ab`, `log_genstep.ab`. This is
  the code that builds the auditable `install.sh` and the audit gate.
- **Most of `src/shlib/install/` is untested:** `apt.ab`, `deb.ab`, `npm.ab`,
  `brew.ab`, `curl.ab`, `fetch.ab`, `github.ab`, `archive.ab`, `patch.ab`,
  `perms.ab`, `dir.ab`, `sh-remote.ab`, `lua_gen.ab`, `browser_ext.ab`,
  `git-config.ab`, `ask.ab` (16 of ~18 modules). Only `cp`, `env`, `rsync`,
  `sh`, `symlink`, `zsh`, `managed_block` have `.test.ab`.
- **Other untested `shlib`:** `pkg.ab`, `tmux.ab`, `time.ab`, `fetch.ab`,
  `fetch_prune.ab`, `parallel.ab`, `sudo.ab`, `os.ab`, `container.ab`.
- **Top-level commands untested:** `shard.ab`, `pipeline.ab`, `vars.ab`.

### The `gen/` directory is excluded from default `lib` runs

`test/test.ab` builds `default_dirs = [SHLIB_DIR, GEN_DIR]` (`test/test.ab:14`)
but only uses it for the `check` and `all` types. The default `lib` type calls
`run_lib_tests([SHLIB_DIR])` (`test/test.ab:22`) — **`GEN_DIR` is omitted**.
Since there are no `*.test.ab` under `gen/` today this is invisible, but it
means even if `gen/` tests are added, the default `./test.sh lib` will not run
them unless the dispatcher is updated. This is a latent trap.

### What each test layer actually does

| Type | Entry | What it runs | Speed |
|---|---|---|---|
| `check` | `test/check.ab` | `amber check <file>` (syntax only) over SHLIB+GEN, parallel via `run_parallel` | fast |
| `lib` (default) | `test/lib.ab` | syntax pre-check, then `amber test <*.test.ab>` over **SHLIB_DIR only**, parallel | fast |
| `smoke` | `test/smoke.ab` | smoke lib + a smoke integration test | medium |
| `integration` | `test/integration.ab` | full pipeline integration (`test/integration/pipeline`) | slow (container) |
| `all` | — | check + lib + smoke + integration | slow |

Note `check` and `lib` duplicate the file-discovery loop
(`find_all_ab_files`/`find_test_files` in `check.ab`/`lib.ab` are near-identical)
and both lean on `run_parallel` (`src/shlib/parallel.ab`), which itself is
untested.

### No AGENTS.md / no documented test commands

There is no `AGENTS.md` in the repo root (the environment lists it as a config
file but it does not exist). The only test entrypoint is `./test.sh [type]`,
discovered via `test/test.ab:8` `print_usage()`. A contributor (human or agent)
has no documented contract for: which command to run before a commit, what
"passing" means, or how to add a test. The Kilo/AGENTS convention expects
lint/typecheck/test commands to be documented so they are run automatically.

### Parallel-test fragility

`run_parallel` (`src/shlib/parallel.ab:3`) computes argument count with
`echo {tasks[0]} | wc -w` and fans out with `xargs -P`. If a task string's
first row has a different token count than later rows (e.g. a path with a
space), `xargs -n` mis-splits arguments. This is untested and is the engine for
the entire test suite and the generation pipeline.

## Proposed Changes

Each item: Effort (S/M/L), Risk (Low/Med/High).

### 1. Add `AGENTS.md` with documented commands — Effort S, Risk Low

Create `AGENTS.md` at the repo root documenting:

- Build: how `copals.sh` is produced (`amber build`), and the `run_amber`
  helper sourced from `copals.sh`.
- Test commands: `./test.sh check`, `./test.sh lib` (default), `./test.sh smoke`,
  `./test.sh integration`, `./test.sh all`, and which to run pre-commit
  (recommend `check` + `lib`).
- How to add a unit test (co-locate `foo.test.ab` next to `foo.ab`).
- The coverage expectation (see change 4).

This satisfies the documented-commands convention so agents/contributors run the
right checks automatically. Pure documentation; no code risk.

### 2. Include `GEN_DIR` in the default `lib` run — Effort S, Risk Low

Change `test/test.ab:22` from `run_lib_tests([SHLIB_DIR])` to
`run_lib_tests([SHLIB_DIR, GEN_DIR])` (and mirror in `all`). This makes the
default unit-test command cover `gen/` once tests exist there. Risk Low: today
there are no `gen/` tests so it is a no-op, but it removes the latent trap.

### 3. Unit-test the `gen/` pipeline (highest-value coverage gap) — Effort L, Risk Low

Add `*.test.ab` for the pure-logic generation modules, prioritising:

- `gen/json_config.ab` / `shlib/json.ab` — jq wrappers are trivially testable
  with fixture JSON (also backs doc 02 change 3).
- `gen/audit.ab` — the security gate; must have tests for forbidden-ext
  detection, whitelist globs, and the ELF/Mach-O magic detection
  (`__FORBIDDEN_EXTS`, `__BINARY_MAGIC` in the compiled `copals.sh`).
- `shlib/fetch_prune.ab` — URL/fetch neutralisation (`--try-prune-fetch-and-urls`)
  is security-relevant and pure-string.
- `shlib/hash.ab` — directory/array hashing already has helpers worth pinning.
- `shlib/parallel.ab` — the test/generation engine; add a test that asserts
  correct arg splitting for multi-token task strings.

Risk Low (tests only) but Effort L because fixtures and the audit cases need
care. This is the single highest-value testing investment: it protects the
auditable-output guarantee.

### 4. A coverage gate — Effort S/M, Risk Low

Add a check (in `check.ab` or a new `test/coverage.ab`) that fails when a
*logic* module lacks a co-located test, with an explicit allowlist for genuine
non-units (entry points like `copals.ab`, `shard.ab`, `pipeline.ab`, container
launchers). This converts the 72%-untested number into a ratchet that only
improves. Pure addition.

### 5. De-duplicate `check.ab` / `lib.ab` discovery — Effort S, Risk Low

`find_all_ab_files` (`test/check.ab:6`) and `find_test_files` (`test/lib.ab:6`)
are the same loop differing only in the glob (`*.ab` vs `*.test.ab`). Extract a
single `find_ab_files(dirs, pattern)` helper. Backs doc 02's theme at the test
layer. Risk Low.

### 6. Harden `run_parallel` and test it — Effort M, Risk Med

Add quoting/escaping to `run_parallel` so multi-word task rows split correctly
(arguably use a delimiter or NUL-separated feed instead of `wc -w`), and add a
unit test. Risk Med because `run_parallel` is on the critical path of both
generation and tests; gate with integration tests.

## Recommendation

Sequence: **1 → 2 → 5 → 4 → 3 → 6.**

- **1** (AGENTS.md) and **2** (include GEN_DIR) immediately: near-zero cost,
  unblock correct test runs.
- **5** and **4** next: tidy the harness and install a coverage ratchet.
- **3** (gen/ unit tests) is the substantive work; prioritise `audit.ab`,
  `fetch_prune.ab`, and the json modules — they are security-relevant and pure.
- **6** (run_parallel hardening) last, gated by integration tests.

## Out of Scope / Risks

- **Container/integration tests** (`test/integration/pipeline`, `smoke`) are
  slow and environment-dependent (podman/docker, debian:testing images per the
  README warning). This doc targets the fast unit layer; making integration
  tests faster or more portable is a separate effort.
- **bashunit vs amber test.** The harness mixes `amber check` (syntax) and
  `amber test`/bashunit (unit). Choosing/standardising one runner is out of
  scope; the proposals work with the current dual setup.
- **Test-isolation for filesystem-touching modules.** Modules like `apt.ab`,
  `npm.ab`, `fetch.ab` mutate the system and are hard to unit-test without
  hermetic fixtures or mocks. Change 3 focuses on pure-logic modules first;
  the system-mutating `install/` modules may need a container-based test
  strategy rather than unit tests.
- **No behavioural changes.** All items are additive (docs/tests/gates); none
  alter generation or install behaviour. The coverage gate (4) must use an
  allowlist so it does not block on intentional non-unit files.
