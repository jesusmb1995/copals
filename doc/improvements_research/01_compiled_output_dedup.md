# 01 — Compiled-Output Deduplication

## Problem Statement

Copals ships as a single compiled Bash artifact (`src/copals.sh`) produced by
running `amber build` over `src/copals.ab`. Amber's compiler inlines the entire
import graph into one flat Bash file and name-mangles every user function per
import site. The result is an artifact that is far larger than the source it is
built from, with the same small functions re-emitted over and over:

- `src/copals.sh` is **5884 lines / ~222 KB**, built from **5049 lines across
  105 `.ab` source files** — the compiled output is larger than the source.
- A single 6-line helper like `_project_root()` is compiled **8 times** into the
  same file under 8 distinct mangled names (`_project_root__65_v0` …
  `_project_root__383_v0`); `bashunit_path()` 5 times; each vendor resolver
  (`jq_resolve`, `j2_resolve`, `jsonnet_resolve`, `jsonschema_resolve`,
  `lua_resolve`) and `resolve_vendor_dir` 3 times each.
- 194 function definitions and 459 call sites in `copals.sh` carry the
  `__<NNN>_v0` per-import-site mangling suffix.

This matters for three reasons. First, Bash parses the whole file on startup,
so a 5884-line script imposes a measurable cold-start tax on every `copals`
invocation. Second, the artifact is the primary auditable surface (the README
advertises an "easily auditable install.sh"); duplicated function bodies make
review harder and inflate diffs on every rebuild. Third, the duplication is
invisible at the source level — contributors cannot see that adding one `import`
silently multiplies compiled size — so there is no natural pressure to keep it
bounded. The problem compounds because Copals produces **several** independent
`amber build` outputs (the main `copals.sh`, `src/gen/postprocess.sh`, the
per-bundle `install.sh`), each of which re-inlines its own import graph from
scratch.

This area overlaps with [02_source_dry_consolidation.md](02_source_dry_consolidation.md),
which covers the source-level duplication that feeds this compiled bloat.

## Evidence

All measurements taken against the current tree.

### Artifact size vs. source size

| Metric | Value |
|---|---|
| `src/copals.sh` lines | 5884 (`wc -l`) |
| `src/copals.sh` bytes | 227,507 (~222 KB) (`wc -c`) |
| Amber compiler version (compiled header) | `version: 0.6.0-alpha` — `src/copals.sh:3` |
| Source `.ab` files | 105 |
| Source LOC (all `.ab`) | 5,049 |
| Compiled Bash function defs (`name__NNN_v0()`) | 194 |
| Mangled call sites (`__NNN_v0`) | 459 |

The compiled artifact is ~16% larger in lines than the entire `.ab` source tree,
despite Bash being more verbose than Amber line-for-line — a direct sign that
the same code is emitted multiple times.

### The compile step

`amber build` is the single inlining pass. There is no intermediate linking or
deduplication stage:

```
src/gen/compile-job.ab:7:    $ amber build {ab_file} {output_path} $ ?
src/container/test.ab:39:    $ amber build {entry} {out_sh} $ ?
copals.sh:157:               amber build "$lib_dir/$script" "$output"
copals.sh:313:               PATH="$lib_dir/vendor:$PATH" amber build "$post_src" "$post_out"
```

`copals.sh` (the root wrapper) invokes `amber build` separately for the main
entry, for `postprocess`, and for `launch-window`; `src/gen/generate.ab:203`
invokes it again per generated bundle to build `install.sh`. Each call re-runs
the inliner independently over its own subgraph, so bloat is replicated per
artifact.

### Duplicated function definitions (verified)

Distinct compiled definitions of the *same* source function, emitted under
per-import-site mangled names:

| Source function | Source defined at | Compiled copies in `copals.sh` |
|---|---|---|
| `_project_root` | `src/vars.ab:4` **and** `src/shlib/vendor.ab:4` | **8** (`__65`, `__75`, `__206`, `__221`, `__262`, `__310`, `__377`, `__383`) |
| `bashunit_path` | `src/vars.ab` | **5** |
| `resolve_vendor_dir` | `src/shlib/vendor.ab:20` | **3** (`__66`, `__222`, `__384`) |
| `jq_resolve` / `j2_resolve` / `jsonnet_resolve` / `jsonschema_resolve` / `lua_resolve` | `src/shlib/vendor.ab:38–71` | **3 each** |
| `temp_file_create` | `src/shlib/temp.ab` | **3** |
| `has_flag` | `src/shlib/flag.ab` | **3** |

Sample of the duplicated bodies — two byte-identical definitions of
`_project_root`, mangled only by their import-site ID:

- `src/copals.sh:393` → `_project_root__174_v0()` (this is the
  `postprocess.sh`-staged copy; see also `src/gen/postprocess.sh:393`)
- `src/copals.sh:444` → `_project_root__179_v0()` (the `vars.ab` copy emitted
  into the main graph)

Contrast — the Amber **stdlib is deduplicated** (one stable copy each), which
proves the compiler *can* collapse identical symbols, it just does not do so for
user modules:

| Stdlib function | Compiled copies in `copals.sh` |
|---|---|
| `replace_regex` | 1 |
| `split_lines` | 1 |
| `file_exists` | 1 |

So the bloat is concentrated in Copals's *own* modules, exactly where
`_project_root` is hand-duplicated across `vars.ab` and `vendor.ab`.

### Per-artifact boilerplate repetition

Every independently compiled `.sh` re-emits the shell-detection prologue and its
own copy of the shared helpers. `src/gen/postprocess.sh:4–15` is byte-identical
to `src/copals.sh:4–15`, and `postprocess.sh` (1100 lines) re-defines its own
`replace_regex`, `split`, `temp_dir_create`, `_project_root`,
`resolve_vendor_dir`, etc. — work already present in the main artifact.

## Root Cause

Three compounding factors, in order of leverage:

1. **Amber inlines the full import graph per `build` and mangles user symbols
   per import site, not per symbol.** The `_v0` suffix is a version stamp; the
   `__NNN` infix is a globally-incrementing ID assigned at each *import site*.
   A function imported by N consumers is therefore emitted N times under N
   distinct names, even though the bodies are byte-identical. The stdlib escapes
   this because Amber treats it as a fixed, single-copy runtime; user modules do
   not get the same treatment. This is an upstream compiler behaviour (Amber
   `0.6.0-alpha`), not a Copals bug.

2. **Source-level duplication multiplies the effect.** `_project_root()` and
   `PROJECT_ROOT` are defined in *two* source modules (`src/vars.ab:4` and
   `src/shlib/vendor.ab:4`), so there are two source symbols to import rather
   than one. Each is pulled into ~4 consumers, producing the 8 compiled copies
   observed. This is tracked separately as doc 02 and is the cheapest lever
   here.

3. **Multiple `amber build` invocations, no shared cache.** `copals.sh`,
   `postprocess.sh`, and each generated `install.sh` are separate build outputs
   with no shared compiled-library stage, so every artifact re-inlines the same
   helpers from scratch and re-emits the shell prologue.

There is no build step today that post-processes, links, or de-duplicates the
compiled output — `compile_ab_file` (`src/gen/compile-job.ab:6`) is a literal
`amber build` followed by an optional `rm`.

## Proposed Changes

Each item is tagged with Effort (S/M/L) and Risk (Low/Med/High).

### (a) Collapse source-level duplicates to a single definition — Effort S, Risk Low

Delete the second copy of `_project_root` / `PROJECT_ROOT` (keep one in
`shlib/vendor.ab` or a new `shlib/paths.ab`; have `vars.ab` import it), and
consolidate the five vendor resolvers into a single parameterised resolver.
This is the work item fully specified in doc 02; it is listed here because it
directly cuts the duplicated compiled copies (8 → ~4 for `_project_root`, 3 → 1
for the vendor resolvers) with no compiler changes and no behavioural risk.
Pair it with (e) below to prove the win in CI.

### (b) Add a build-time `dedup` post-pass over compiled `.sh` — Effort M, Risk Med

After `amber build`, run a deterministic transform that detects byte-identical
function bodies emitted under different `__NNN_v0` names, keeps one canonical
copy, and rewrites all call sites to the canonical name. Concretely: parse
`name__NNN_v0() { … }` blocks, hash the body, group by hash, pick the lowest ID
as canonical, and `sed`-rewrite the rest. This attacks the compiler limitation
directly without depending on upstream Amber. Risk is Medium because the
transform must be robust to Amber's output format (the `0.6.0-alpha` header
means the format is still changing), and a bad rewrite can produce a script that
parses but misbehaves at runtime. Mitigate with (e) and the existing integration
tests (`test/integration/`).

### (c) Introduce a sourced runtime-library convention — Effort L, Risk Med

Stop compiling every import into the entry script. Instead, build small, stable
`*.sh.lib` files for shared helpers (`paths`, `vendor`, `fs`, `text`) and
`source` them from `copals.sh` at runtime, so each symbol exists exactly once
across the whole installation. This is the structurally correct fix and also
shrinks per-bundle `install.sh` output, but it is a large change: it requires a
new build target type, a load-path convention, and careful handling of the
"self-contained single file" guarantee the README advertises for `install.sh`.
Defer until (a)+(b)+(e) are measured.

### (d) Lazy command dispatch in `copals.sh` — Effort M, Risk Med

`src/copals.ab` unconditionally imports `main_generate`, `main_container`,
`shard_main`, `pipeline_main`, `skill_main` (`src/copals.ab:13–17`), so every
invocation — even `copals help` — parses the entire transitive graph. Splitting
the dispatcher so that sub-command bodies are `source`d (or compiled into
separate files) only when invoked would cut the common-case parse cost without
touching the compiler. Same single-file guarantee caveat as (c).

### (e) CI size/duplication guard — Effort S, Risk Low

Add a check to the test pipeline (the project already runs `test.sh`) that
asserts, after a build: (1) `copals.sh` line count stays under a budget, (2) no
user symbol is defined more than `K` times (e.g. `rg -o
'^[a-zA-Z_][a-zA-Z0-9_]*__...' | sed … | uniq -c` bounded), and (3) total
bytes stay under a budget. This makes bloat a visible, failing signal instead of
a silent drift, and it gives (a) and (b) a measurable target. Pure addition, no
runtime risk.

### (f) Upstream engagement — Effort S, Risk Low

File/track an Amber issue requesting per-symbol (rather than per-import-site)
mangling for user modules, or a `--release`/`--dedup` flag, citing the
8×`_project_root` / 3×`resolve_vendor_dir` numbers above. Low cost, potentially
the highest-leverage fix if the compiler adopts it; no dependency on it for the
local fixes.

## Recommendation

Sequence: **(a) → (e) → (b) → evaluate (c)/(d), pursue (f) in parallel.**

- Start with **(a)** (source consolidation) and **(e)** (CI guard) together:
  they are both Low risk, mostly mechanical, and (e) gives a hard before/after
  number for (a) — likely removing 3–5 compiled copies of `_project_root` and
  the vendor resolvers immediately.
- Then attempt **(b)**, the build-time dedup pass. It is the highest-value
  structural fix available without depending on Amber upstream, and the CI guard
  from (e) makes it safe to land.
- Reserve **(c)** and **(d)** for after (b) is measured: if (b) brings the
  artifact under an acceptable budget, the much larger sourcing refactor may not
  be worth its risk.
- **(f)** is essentially free and should be opened now regardless, since an
  upstream fix would eventually obsolete (b).

## Out of Scope / Risks

- **Behavioural equivalence is mandatory.** Every change in this document must
  keep `copals.sh`, `postprocess.sh`, and the generated `install.sh`
  observationally identical. None of (a)/(b)/(e) change logic; (c)/(d) do, and
  must be validated by the existing `test/integration/pipeline` and
  `test/integration/smoke` suites.
- **Upstream output format volatility.** The `0.6.0-alpha` compiler stamp means
  the `__NNN_v0` mangling scheme and the emitted boilerplate (lines 4–15) can
  change between Amber releases. Any post-pass in (b) must be pinned to a
  compiler version and re-validated on bumps; it cannot assume a stable layout.
- **The shipped `install.sh` artifact.** Its single-file, zero-dependency
  contract (README "Core Features") is user-facing and security-relevant. (c)
  and (d) must not break that contract for the installer output; if they do,
  they apply to `copals.sh`/`postprocess.sh` only.
- **`postprocess.sh` and other independent builds.** They suffer the same
  inlining and would each need the same dedup treatment; scoping (b) to only
  `copals.sh` first is acceptable, but the duplication there remains until
  extended.
- **Replacing or forking Amber** is explicitly out of scope. All proposals keep
  `amber build` as the compiler; (b)/(c) layer on top of its output.
- **Doc 02 overlap.** Source-level DRY (the `vars.ab`/`vendor.ab`
  `_project_root` duplication, the 5× vendor resolver pattern, the
  `json_config.ab`/`json.ab` duplication) is owned by
  [02_source_dry_consolidation.md](02_source_dry_consolidation.md). This document
  depends on (a) of doc 02 but does not redefine it.
