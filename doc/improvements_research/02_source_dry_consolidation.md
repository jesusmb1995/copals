# 02 — Source-Level DRY & Module Consolidation

## Problem Statement

Copals is written in Amber (`.ab`), whose modules are imported with `import`.
At the **source** level the same logic is written more than once. This is the
cheapest, lowest-risk class of improvement: every duplication here is a place
where a future fix must be applied N times, and where copy-paste drift has
already begun.

This document is the source-level companion to
[01_compiled_output_dedup.md](01_compiled_output_dedup.md). Doc 01 covers the
compiled-output bloat that *results* from importing these modules; this doc
covers the duplications that exist *in the source itself*, independent of the
compiler. Consolidating them improves source readability immediately and also
reduces the number of symbols each consumer pulls in (a secondary win for the
compiled artifact).

## Evidence

All references are to the current tree. Amber snippets are illustrative
before/after, not applied patches.

### (a) `_project_root()` is copy-pasted in two modules

The exact same function body lives in **both** `src/vars.ab` and
`src/shlib/vendor.ab`:

`src/vars.ab:4`
```amber
fun _project_root(): Text {
    if file_exists("src/copals.ab") {
        const pwd_val = pwd()
        return replace_regex(pwd_val, "/[^/]+$", "", true)
    }
    return pwd()
}
```

`src/shlib/vendor.ab:4` — byte-identical body:
```amber
fun _project_root(): Text {
    if file_exists("src/copals.ab") {
        const pwd_val = pwd()
        return replace_regex(pwd_val, "/[^/]+$", "", true)
    }
    return pwd()
}
```

Each module then derives its own `PROJECT_ROOT`/`_REPO_GEN_DIR` constant from
it (`src/vars.ab:12`, `src/shlib/vendor.ab:12`). Because there are two source
symbols, importers pull in one or the other, which is why doc 01 measures 8
compiled copies of `_project_root`. The heuristic — "if `src/copals.ab` exists
we are at the repo root, so strip the last path segment" — is also fragile (see
the `// TODO must be handled without repo root being outside copals...` comment
at `src/vars.ab:14`), and the fragility is now duplicated.

### (b) Five vendor resolvers are the same 4-line pattern

`src/shlib/vendor.ab:38-71` defines five functions whose bodies differ only in
the tool name:

```amber
fun jq_resolve(): Text {
    if VENDOR_DIR == "" { return "jq" }
    return "{VENDOR_DIR}/jq"
}
fun j2_resolve(): Text {
    if VENDOR_DIR == "" { return "j2" }
    return "{VENDOR_DIR}/j2"
}
// ... jsonnet_resolve, jsonschema_resolve, lua_resolve identical ...
pub const JQ = jq_resolve()
pub const J2 = j2_resolve()
pub const JSONNET = jsonnet_resolve()
pub const JSONSCHEMA = jsonschema_resolve()
pub const LUA = lua_resolve()
```

That is five copies of `if VENDOR_DIR == "" return "<name>" else return
"{VENDOR_DIR}/<name>"`. Adding a sixth vendored tool means copy-pasting a sixth
time.

### (c) `json_config.ab` self-declares duplication of `json.ab`

`src/gen/json_config.ab:4` carries the literal comment:

```amber
// TODO reuse from shlib/json
```

Both modules wrap `jq`, but with different shapes:

`src/shlib/json.ab:12` — generic key lookup:
```amber
pub fun json_value(json_filepath: Text, key: Text): Text? {
    const val = $ {JQ} -r --arg key {key} '.[\$key]' {json_filepath} $ ?
    if val == "null" { echo("key '{key}' not found ..."); fail 1 }
    return val
}
```

`src/gen/json_config.ab:5` — repo-scoped lookup (filters `.repositories[]`):
```amber
fun _json_value(config_file: Text, id: Text, key: Text): Text? {
    return $ {JQ} -re --arg id {id} --arg key {key} \
        '.repositories[] | select(.id == "{id}") | .[\$key]' {config_file} $ ?
}
```

They overlap conceptually (both "read a value from JSON via jq") but differ in
scope (whole-doc key vs. repository row). The TODO is a standing acknowledgement
that the split is accidental, not intentional.

### (d) `fs.ab` shadows / reimplements stdlib helpers

`src/shlib/fs.ab` imports from `std/fs` (`file_glob`) yet also hand-rolls:

- `file_ext` (`src/shlib/fs.ab:14`) via `echo "{path}" | cut -d. -f2-`
- `abspath` (`src/shlib/fs.ab:25`) via `realpath {path}`
- `realpath_or_empty` (`src/shlib/fs.ab:29`) via a `2>/dev/null || true` wrapper
- `rm_force` (`src/shlib/fs.ab:41`) and `rm_glob` (`src/shlib/fs.ab:33`) — two
  flavours of `rm` that differ only in flags

These need a check against what `std/fs` already exports to avoid shadowing
stdlib behaviour with subtly different local copies (e.g. `file_ext` on a file
with no extension returns the whole name, an edge case worth documenting).

### (e) Import fan-out concentrates on a few modules

How often the most-shared modules are re-imported across the source tree:

| Imported module | Importers |
|---|---|
| `std/fs` | ~34 |
| `std/test` | ~21 |
| `std/env` | ~19 |
| `std/text` | ~18 |
| `temp.ab` | ~10 |
| `vendor.ab` (+ `../shlib/vendor.ab`) | ~12 combined |

Every extra symbol defined in these hot modules is multiplied across this many
importers in the compiled output. Keeping `vendor.ab`/`vars.ab`/`temp.ab`
minimal is disproportionately valuable — which is exactly why (a) and (b)
above matter.

## Proposed Changes

Each item: Effort (S/M/L), Risk (Low/Med/High), migration notes.

### 1. Single canonical `_project_root` — Effort S, Risk Low

Pick **one** home for `_project_root`/`PROJECT_ROOT`. Recommended: a new
`src/shlib/paths.ab` (or fold into `vendor.ab` since it already computes paths),
then:

- `src/vars.ab` imports `PROJECT_ROOT` instead of redefining it.
- `src/shlib/vendor.ab` imports it too.

Migration: mechanical. The two existing copies are byte-identical, so behaviour
is preserved by construction. Run `test.sh` (lib + smoke) after. This removes
one source symbol and (per doc 01) collapses several compiled copies.

Risk note: Amber `pub const` is evaluated at module load; confirm there is no
load-order hazard between `vars.ab` and `vendor.ab` (neither imports the other
today, so the new shared module must not create a cycle).

### 2. Generic `resolve_vendor_tool(name)` — Effort S, Risk Low

Replace the five resolvers with one parameterised helper:

```amber
// after: resolve_tool(name: Text): Text { ... }
pub fun resolve_vendor_tool(name: Text): Text {
    if VENDOR_DIR == "" { return name }
    return "{VENDOR_DIR}/{name}"
}
pub const JQ        = resolve_vendor_tool("jq")
pub const J2        = resolve_vendor_tool("j2")
pub const JSONNET   = resolve_vendor_tool("jsonnet")
pub const JSONSCHEMA = resolve_vendor_tool("jsonschema")
pub const LUA       = resolve_vendor_tool("lua")
```

Migration: keep the existing `pub const JQ`/`J2`/... names so no importer
changes. Pure refactor; the public surface (`JQ` etc.) is unchanged. Add a
`.test.ab` asserting `resolve_vendor_tool("jq")` returns the right path for
both `VENDOR_DIR == ""` and populated cases.

### 3. Merge `json.ab` + `json_config.ab` — Effort M, Risk Low/Med

Move the repo-scoped helpers into `src/shlib/json.ab` so there is one JSON
module:

```amber
// shlib/json.ab
pub fun json_value(file, key): Text?            // whole-doc key (existing)
pub fun repo_json_value(file, id, key): Text?   // from json_config._json_value
pub fun repo_json_value_or(file, id, key, def): Text
pub fun repo_json_list(file, id, key): [Text]?
```

Then delete `src/gen/json_config.ab` and repoint its importers
(`src/gen/process-repo.ab`, `src/gen/generate.ab`) at the consolidated module.
Delete the `// TODO reuse from shlib/json` marker.

Risk: Med only because `json_config.ab` uses `-re` (raw+exit-on-null) and a
`select(.id == "{id}")` filter interpolated differently from `json.ab`'s
`--arg` style; preserve the exact jq filter strings to avoid subtle quoting
changes. Add regression tests covering the repo-scoped lookups before deleting
the old module.

### 4. Audit `fs.ab` against `std/fs` — Effort S, Risk Low

For each local helper in `src/shlib/fs.ab` (`file_ext`, `abspath`,
`realpath_or_empty`), determine whether `std/fs` already provides an equivalent.
If yes, delegate; if no, keep it but add a one-line doc comment stating the
behaviour (especially `file_ext`'s no-extension edge case). Consolidate
`rm_force`/`rm_glob` into one `rm(path, recursive: Bool = true, force: Bool =
true)` if Amber default args make the callsites cleaner.

## Recommendation

Sequence: **1 → 2 → 3 → 4.**

- **1** and **2** first: both are Size S, Risk Low, mechanical, and directly
  shrink the hottest modules (`vendor.ab`, `vars.ab`). They also give doc 01's
  CI guard an immediate before/after number.
- **3** next: slightly larger because it touches two modules and jq filter
  strings, but it retires a standing TODO and consolidates all JSON access.
- **4** last: a tidy-up pass, lowest urgency.

Land 1 and 2 together in one change; gate with `test.sh lib` + `test.sh smoke`.

## Out of Scope / Risks

- **Compiled-output bloat itself** is doc 01's concern. Consolidating source
  reduces the number of *symbols* imported, but Amber still re-inlines each
  imported symbol per consumer. Source DRY is necessary but not sufficient for
  artifact dedup; do not expect the 5884-line `copals.sh` to shrink dramatically
  from these changes alone — that requires doc 01's build-time dedup pass.
- **Amber import semantics.** A function imported from module A into module B is
  emitted into B's compiled output; consolidating definitions does not change
  that the compiler copies them. The win here is source maintainability and a
  smaller symbol set, not eliminating inlining.
- **Circular imports.** Introducing a shared `paths.ab` consumed by both
  `vars.ab` and `vendor.ab` must not create a cycle (vendor → paths → vendor).
  Verify the dependency direction is one-way before landing change 1.
- **Public API stability.** `JQ`, `JSONNET`, `PROJECT_ROOT`, etc. are
  referenced across the tree; changes must preserve these names. The proposals
  above keep every public name and only consolidate the *implementations*.
- **jq filter exactness (change 3).** The repo-scoped filters use both `--arg`
  and direct `{id}` interpolation in different places; the merge must preserve
  the exact filter text to avoid behaviour changes on ids containing special
  characters.
