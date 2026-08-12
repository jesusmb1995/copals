# 03 — Modular Hook / Plugin System

## Problem Statement

Hooks are Copals' primary extension mechanism: a user supplies Amber (`.ab`)
or Lua (`.lua`) scripts that replace or augment generation and deployment for a
repository. The mechanism is powerful but **ad-hoc**:

1. **No two hook kinds speak the same environment.** The four hook call-sites
   pass overlapping-but-different sets of env vars, and at least two pass the
   wrong binary for an advertised variable. A hook author must read the Copals
   source to discover what is available, and the same logical hook behaves
   differently depending on whether it is `.ab` or `.lua`.
2. **Discovery is filename magic.** Hooks are found by globbing
   `generate_{repo_id}.ab`, `install_{repo_id}.ab*`, and
   `generate_{repo_id}_postrender.{ab,lua}`. There is no manifest, no
   metadata, no versioning.
3. **Nothing is reusable or shareable.** The README lists "Shareable & Modular
   Plugin System" as Future Work. Today, a useful hook written for one user's
   repo cannot be imported into another user's preset without manual copying.

This document scopes a modular, well-contracted hook system aligned with that
Future Work item. It overlaps with [doc/hooks.md](../hooks.md) (the user-facing
hook guide) but focuses on the *internal* contract and packaging, not usage.

## Evidence

### Hook inventory and their (inconsistent) environments

All four hook invocation sites, verified in the current tree:

| # | Hook kind | Call site | Filename convention | Executor | Parallel? |
|---|---|---|---|---|---|
| 1 | Generate (per-repo) | `src/gen/process-repo.ab:29` | `generate_{repo_id}.ab` | `amber` | Yes (`run_parallel`) |
| 2 | Generate-post (global) | `src/gen/generate.ab:143` | `generate_post.ab` | `amber` | No (once) |
| 3 | Post-render (per-repo) `.ab` | `src/gen/generate.ab:165` | `generate_{repo_id}_postrender.ab` | `amber` | No (serial loop) |
| 4 | Post-render (per-repo) `.lua` | `src/gen/generate.ab:167` | `generate_{repo_id}_postrender.lua` | `lua` | No (serial loop) |
| 5 | Install (per-repo) | `src/gen/generate.ab:183` (`build_installer`) | `install_{repo_id}.ab*` | jinja-render → compiled into `install.ab` | n/a (compile-time) |

The environment variables each receives:

| Var | Generate(1) | Gen-post(2) | Postrender .ab(3) | Postrender .lua(4) |
|---|---|---|---|---|
| `SOURCE_PATH` | yes | — | — | — |
| `TARGET_PATH` | yes | — | yes | yes |
| `CACHE_PATH` | yes | — | — | — |
| `REPO_ID` | yes | — | yes | yes |
| `GEN_DIR` | yes | — | — | — |
| `HOOKS_DIR` | yes | — | yes | yes |
| `CONFIG_FILE` | yes | yes | yes | yes |
| `DEST_DIR` | — | yes | yes | yes |
| `SOURCE_IGNORED` | — | yes (`=""`) | yes (`=""`) | — |
| `J2_BIN` | **`{J2}`** | **`{JQ}`** | **`{JQ}`** | — |

### Concrete bugs surfaced by this contract

1. **`J2_BIN` carries the wrong binary in two of three sites.** The variable
   is named after the Jinja2 renderer (`j2`), and the generate hook correctly
   sets `J2_BIN={J2}` (`src/gen/process-repo.ab:29`). But the generate-post and
   post-render `.ab` sites set `J2_BIN={JQ}` (`src/gen/generate.ab:143` and
   `:165`) — i.e. they advertise a Jinja2 binary but hand the hook `jq`. Any
   hook that trusts `J2_BIN` to render a template will run `jq` on it.

2. **`.lua` post-render hooks get a strictly smaller environment than `.ab`
   ones** for the *same* hook kind (`src/gen/generate.ab:165` vs `:167`). The
   `.lua` variant is missing `SOURCE_IGNORED` and `J2_BIN`. A user switching a
   hook from `.ab` to `.lua` (or vice-versa) silently loses/gains variables.

3. **`SOURCE_IGNORED` is always `""`.** It is set at `generate.ab:143` and
   `:165` but never to a meaningful value — it appears to be a vestigial or
   half-wired flag.

### Discovery by filename magic

`build_installer` (`src/gen/generate.ab:183`) globs `install_{id}.ab*` and
branches on `file_ext` to decide rendering; the post-render loop
(`generate.ab:159-160`) checks for `.ab` *or* `.lua` with `file_exists`. There
is no central registry of "which hook kinds exist" or "what contract each
requires" — the contract is implicit in four scattered `$. . .$` blocks.

### Concurrency model and documented races

`process_repos` (`src/gen/generate.ab:128-138`) and `render_jinja_tree`
(`:56-63`) fan out via `run_parallel` (`src/shlib/parallel.ab`), which uses
`xargs -P {MAX_JOBS}` with `MAX_JOBS = 8` (`generate.ab:25`). Post-render hooks
run in a **serial** loop (`generate.ab:158`) with an explicit
`// TODO: should also use parallel tasks for faster processing` comment
(`generate.ab:157`). The serial execution is not arbitrary:
[doc/hooks.md](../hooks.md) ("Gotchas → Parallel generate race") documents that
parallel `rsync --delete` can clobber nested targets, which is why post-render
is serialised in the first place. Any move to parallelise it must respect this.

### Documented design requirements (existing)

[doc/hooks.md](../hooks.md) "Design Requirements" states hooks must be
**idempotent** and must **kill the program on failure** via the
`*_impl(): Null?` + infallible wrapper pattern. This is a contract that the
plugin work should preserve and make machine-checkable.

## Proposed Changes

Each item: Effort (S/M/L), Risk (Low/Med/High).

### 1. Unify the hook environment via a single `hook_env` helper — Effort S, Risk Low

Introduce one helper (e.g. in `src/shlib/hooks.ab`) that builds the canonical
environment for a given hook kind, and have all four call-sites use it:

```amber
// Canonical set: every hook kind gets all of these.
// Hook kind only toggles a few kind-specific vars.
pub fun hook_env(kind: Text, ctx: HookContext): Text {
    // always: CONFIG_FILE, REPO_ID, TARGET_PATH, HOOKS_DIR, DEST_DIR,
    //         CACHE_PATH, GEN_DIR, SOURCE_PATH, J2_BIN=<the real j2>
    // kind-specific SOURCE_IGNORED semantics documented
}
```

This **fixes the `J2_BIN={JQ}` bug** (all sites resolve the real `J2`), removes
the `.ab`/`.lua` drift (both get the full set), and makes `SOURCE_IGNORED`
either meaningful or removed. Risk Low: it is a refactor of four call-sites,
gated by existing tests; the only behavioural change is the bug fix.

### 2. Replace filename-magic discovery with a hook manifest — Effort M, Risk Med

Declare hooks in the repo config instead of (or in addition to) the filename
convention. For example, extend the config schema
(`res/config.schema.json`) so a repository entry may list its hooks:

```jsonnet
{
  id: "nvim",
  target: ".config/nvim",
  hooks: {
    generate: "generate_nvim.ab",
    postrender: "generate_nvim_postrender.lua",
    install:   "install_nvim.ab",
  },
}
```

The generator then reads the manifest rather than globbing. Keep the current
filename convention as a **fallback** during transition so existing bundles
keep working unmodified. Risk Med: touches the config schema and `process-repo`
/ `build_installer`; needs schema-version awareness and migration tests.

### 3. Plugin packaging for shareable hooks — Effort L, Risk Med/High

Align with the README Future Work item. Define a packaging format for a
shareable "profile/plugin" that bundles one or more repos *and* their hooks,
importable into a preset:

- A plugin is a directory (or git URL) with `repos/`, `repo-hooks/`, and a
  small `plugin.jsonnet` manifest (id, version, deps).
- `copals plugin add <url>` clones it into a plugins dir and registers it.
- Presets reference plugins by id; the generator merges plugin `repo-hooks/`
  into the effective hooks set (namespaced by plugin id to avoid collisions).

Risk Med/High: introduces a new top-level command, a plugins store, name
collision rules, and version resolution. This is the largest item and should
follow 1 and 2.

### 4. Documented hook lifecycle state machine — Effort S, Risk Low

Add a section to [doc/hooks.md](../hooks.md) (or a new `doc/hook_lifecycle.md`)
that is the single source of truth for ordering:

```
generate (parallel, per-repo) ──► generate_post (once)
   └─► render_jinja_tree (parallel)
        └─► postrender (serial, per-repo)
             └─► [bundle built]
                  └─► install hooks compiled into install.sh (deploy-time)
```

State the parallel-vs-serial guarantees and the `--delete` race explicitly so
hook authors know when invariants hold. Pure documentation; no code risk.

### 5. Hook skeleton generator — Effort S/M, Risk Low

Add `copals hook new <kind> <repo_id>` that emits a compliant skeleton
(correct `*_impl(): Null?` wrapper, reads the canonical env vars, returns
`Null?`) into `repo-hooks/`. Lowers the barrier to correct hooks and bakes in
the contract from change 1. No runtime risk.

## Recommendation

Sequence: **1 → 4 → 5 → 2 → 3.**

- **1** (unify env / fix `J2_BIN`) first: it fixes live bugs and is the
  prerequisite contract that 2, 3, and 5 all assume.
- **4** documents the lifecycle that 1 establishes — cheap and immediately
  useful.
- **5** builds on the contract, improving DX.
- **2** moves discovery to a manifest, gated by a fallback for backward
  compatibility.
- **3** (plugin packaging) is the strategic, README-aligned goal; land it last
  once the contract and manifest are stable.

## Out of Scope / Risks

- **Backward compatibility.** Existing in-tree hooks rely on the filename
  convention and the current (buggy) env. Changes 1 and 2 must preserve
  behaviour for hooks that do not opt into the manifest — use fallback discovery
  and keep all currently-passed env vars present (with `J2_BIN` corrected).
- **The `--delete` rsync race** ([doc/hooks.md](../hooks.md) "Gotchas") is a
  real correctness constraint on parallelism. Change 4 documents it; nothing in
  this doc removes the serial post-render guarantee without solving that race.
- **Install hooks are special.** They are jinja-rendered and *compiled into*
  `install.sh` (`build_installer`, `res/install.ab.j2`), so they do not run at
  generate time and cannot receive a runtime env in the same way. Change 1's
  unified contract applies to the generate/postrender hooks; install hooks need
  a parallel but distinct (compile-time) treatment tracked separately.
- **`SOURCE_IGNORED` semantics are unclear** (always `""`). It is out of scope
  to invent a meaning; change 1 either wires it properly or removes it, decided
  when the canonical env is defined.
- **Plugin security.** Change 3 introduces remote hook execution; a full
  treatment of signing/trust is out of scope here but must precede any
  `plugin add <url>` shipping.
