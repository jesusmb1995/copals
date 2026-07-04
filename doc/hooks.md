# Hooks

Hooks are user-provided Amber scripts that replace or augment the default generation/deployment behavior.

## Generation Hooks

Located at `{user_dir}/repo-hooks/generate_{repo_id}.ab`.

If present, they replace the default rsync-based copy for that repository during `generate`. Receives environment variables: `SOURCE_PATH`, `TARGET_PATH`, `CACHE_PATH`, `REPO_ID`, `GEN_DIR`.

This allows custom logic for fetching external sources, transforming data, or performing pre-install audits.

## Install Hooks

Located at `{user_dir}/repo-hooks/install_{repo_id}.ab` (can be `.ab` or another extension).

These are the actual deployment steps. During `build_installer()` they are:
1. Globbing per repo ID
2. Copied into a temporary directory
3. Optionally rendered through Jinja2 (if `.j2` extension)
4. Compiled together with `install.ab.j2` into the final `install.sh` bundle

The generated `install.sh` imports and calls each `install_{repo_id}()` function in sequence.

## Design Requirements

- Must be **idempotent** — running multiple times produces the same result.
- Must **kill the program on failure** — use `*_impl(): Null?` with `?` propagation, wrapped by an infallible `install_x()` that calls `exit(1)` on failure.

## Jinja2 Templates

All `*.j2` files in the destination tree are rendered after repo processing using the validated config JSON as context, enabling dynamic hook content.
