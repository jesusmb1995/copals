# AGENTS.md

Guidance for agents and contributors working on Copals.

## What this is

Copals is a devtools generator written in [Amber](https://amber-lang.com/)
(`.ab`), which compiles to Bash. The shipped artifact is the compiled
`src/copals.sh`. Optional build-time tools (amber, jq, jsonnet, j2, lua,
jsonschema) are vendored under `vendor/` and run inside the project's own
container images.

## Environment setup

Amber is not assumed to be on the host PATH. The project ships a vendored
binary at `vendor/amber`. To run amber/ tests locally, put the vendored tools
on PATH first:

```sh
PATH="$PWD/vendor:$PATH"
```

Or populate `vendor/` from scratch (fetches the toolchain) with:

```sh
sh dependencies.sh
```

CI runs tests inside the container image via:

```sh
COPALS_LIB_DIR=/copals sh /copals/test.sh
```

## Build

Compile an Amber entrypoint to Bash:

```sh
amber build src/copals.ab /tmp/copals.sh   # main CLI artifact
```

`copals.sh` (repo root) is a thin wrapper that sources helpers and exposes
`run_amber`, `run_local`, `run_container`. To run the CLI without pre-building:

```sh
sh copals.sh <command> [args...]        # e.g. sh copals.sh help
```

## Test (run these before committing)

Entry point is `test.sh`, which dispatches via `test/test.ab`:

```sh
sh test.sh check        # 'amber check' syntax/lint pass over src/shlib + src/gen (parallel)
sh test.sh lib          # co-located unit tests (*.test.ab) — the default
sh test.sh smoke        # smoke lib + a smoke integration test
sh test.sh integration  # full pipeline integration (needs podman/docker)
sh test.sh all          # check + lib + smoke + integration
```

**Pre-commit minimum:** `sh test.sh check && sh test.sh lib`.

Tests are discovered non-recursively per directory: `sh test.sh lib` scans
`src/shlib/*.test.ab` and `src/gen/*.test.ab`. To add a unit test, co-locate a
`foo.test.ab` next to the module `foo.ab` and use the existing tests
(e.g. `src/shlib/fs.test.ab`) as the pattern:

```amber
import { assert_eq } from "std/test"
import { my_fn } from "my_module.ab"

test "my_fn: does the thing" {
    assert_eq(my_fn(input), expected)
}
```

## Conventions

- Failable functions return `T?`; unwrap with `?`, recover with `failed { }`,
  or discard with `trust` (avoid `trust` unless justified — the compiler warns
  on empty `failed {}` blocks).
- Avoid bare `{` inside Amber string literals — it triggers interpolation;
  escape as `\{` (close braces `}` are fine plain).
- `lines`, `status`, and other names are reserved keywords — do not use them as
  identifiers.
- See `doc/improvements_research/` for scoped improvement proposals (testing,
  DRY, hooks, cross-platform, error handling, compiled-output dedup).
