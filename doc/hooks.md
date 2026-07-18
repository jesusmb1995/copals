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

## Private repos (host-clone, no in-container fetch)

Some repos are private (e.g. a personal nvim plugin) and must not be fetched
inside the copals container, which has no credentials. The recommended pattern
is to clone them **on the host** once, then copy the clone into the build tree.

1. **Declare the repo** in `config-presets/lib/repos.libsonnet` with
   `clone: true` and `enabled: true`. Point `target` at where it must land in
   the build tree (e.g. a nested path like `.config/nvim/lazy/<plugin>`).

2. **Host clone** via `copals user-clone <profile> <config>`. This runs
   `git clone` on the host (credentials available) and checks out the commit
   pinned elsewhere (e.g. an nvim `lazy-lock.json`). The clone lives at
   `user/repos/<id>` and is gitignored — it is a local working copy, never
   committed.

3. **No custom generate hook needed** for a plain copy. The default
   `process-repo` step already rsyncs `user/repos/<id>` (minus `.git`) into the
   `target` path. A `generate_<id>.ab` hook is only required for extra
   transformation.

4. **Re-stage after destructive steps with a post-render hook.**
   If another repo's generate step prunes your folder (e.g. nvim's plugin
   pre-fetch removes any `lazy/` entry it cannot resolve to a network URL), add
   `generate_<id>_postrender.ab`. Post-render hooks run **after** all repo
   copies and jinja rendering, so they always see the final state. The hook
   copies `user/repos/<id>` into `TARGET_PATH` (passed as env, =
   `{dest}/{target}`) and excludes `.git`. Derive the source from `HOOKS_DIR`:
   `dirname(HOOKS_DIR)/repos/<id>`.

5. **Install is usually a no-op.** If the plugin is exposed at runtime through
   an existing symlink (e.g. `install_nvim` symlinks
   `~/.local/share/nvim/lazy` -> `src/.config/nvim/lazy`), then a real
   `install_<id>` that rsyncs the dir would copy it onto itself via the
   symlink. In that case make `install_<id>.ab` an empty function — it still
   must exist because the installer dispatcher imports `install_<id>()` for
   every enabled repo.

### Gotchas
- **Parallel generate race**: repos copy in parallel (`run_parallel` in
  `process-repo.ab`). A nested target (e.g. `.config/nvim/lazy/<plugin>` inside
  `.config/nvim`) can be clobbered by the parent repo's `--delete` rsync. The
  post-render hook (serialized, after all copies) avoids this. If you must stage
  during the parallel phase, exclude the nested dir from the parent's `--delete`.
- **Prune, not network fetch**: declare the plugin as a local `dir=` plugin in
  its spec so the pre-fetch skips the network; the host clone supplies the
  actual files.

