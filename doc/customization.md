# Customization

## Schema

`config.schema.json` (JSON Schema Draft 2020-12) defines the configuration structure:

- Top-level fields: `Description`, `base_image`, `i3` (mode, launcher), `ai_tools`, `browsers`, `languages`, `system_tools` (boolean per tool)
- `repositories` array: `id`, `url`, `target`, `enabled`, `clone`, `name`, `inplace`, `impl`, `impl_variants`

## Generation Hooks (`generate_{repo_id}.ab`)

Place in `{user_dir}/repo-hooks/`. If present, they replace the default rsync-based copy for that repository. Receives env vars: `SOURCE_PATH`, `TARGET_PATH`, `CACHE_PATH`, `REPO_ID`, `GEN_DIR`.

## Install Hooks (`install_{repo_id}.ab`)

Place in `{user_dir}/repo-hooks/`. These are the actual deployment steps — collected during `build_installer()`, globbed per repo ID, optionally rendered through Jinja2 (`.j2` extension), and compiled with `install.ab.j2` into the final `install.sh` bundle. The generated installer calls each `install_{repo_id}()` function in sequence.

Hook requirements: must be **idempotent**, **kill the program on failure**, and use a `*_impl(): Null?` helper with `?` propagation wrapped by an infallible `install_x()` that calls `exit(1)` on failure.

## Install shlib Modules (`src/shlib/install/`)

Reusable Amber modules for deployment operations:

| Module | Functions |
|---|---|
| `apt.ab` | `apt_install`, `apt_install_or_die` |
| `archive.ab` | `fetch_zip_and_deploy`, `fetch_zip_and_deploy_or_die` |
| `brew.ab` | `brew_install`, `brew_install_or_die` |
| `cp.ab` | `cp_or_die`, `copy_into_home`, `copy_into_home_or_die` |
| `curl.ab` | `install_via_curl`, `install_via_curl_or_die` |
| `deb.ab` | `install_deb`, `install_deb_or_die`, `install_deb_url` |
| `env.ab` | `env_vars_get`, `env_vars_get_or_die` |
| `fetch.ab` | `download_to_target_env` |
| `git-config.ab` | `setup_global_gitignore`, `setup_global_gitignore_or_die` |
| `github.ab` | `install_github_deb`, `install_github_deb_url` |
| `npm.ab` | `install_via_npm`, `install_via_npm_or_die` |
| `patch.ab` | `apply_patch_at_home_or_die` |
| `rsync.ab` | `rsync_into_home`, `rsync_or_die_into_home`, `rsync_or_die_opts` |
| `sh.ab` | `execute_sh_at_home`, `execute_sh_at_home_or_die` |
| `sh-remote.ab` | `execute_remote_sh`, `execute_remote_sh_or_die` |
| `symlink.ab` | `symlink_into_home`, `symlink_into_home_or_die` |
| `zsh.ab` | `execute_zsh_at_home`, `execute_zsh_at_home_or_die` |

## Shared Library (`src/shlib/`)

| Module | Key functions |
|---|---|
| `vendor.ab` | `JQ`, `J2`, `JSONNET`, `JSONSCHEMA` constants |
| `container.ab` | `build_image`, `image_exists`, `remove_image`, `ensure_stop`, `update_container` |
| `flag.ab` | `has_flag`, `flag_value` |
| `hash.ab` | `hash_dir`, `hash_arr`, `read_state_hash`, `write_state` |
| `json.ab` | `to_json_array`, `write_json_array`, `json_value`, `json_value_or` |
| `jsonnet.ab` | `jsonnet_render`, `jsonnet_render_file`, `jsonnet_render_tla`, `jsonnet_render_tla_file` |
| `parallel.ab` | `run_parallel` |
| `cache.ab` | `default_cache_dir`, `get_cache_dir` |
| `cmd.ab` | `has_cmd`, `which_cmd`, `require_or_die` |
| `fs.ab` | `filename`, `file_ext`, `abspath`, `realpath_or_empty`, `rm_glob`, `match_files` |
| `temp.ab` | `temp_file_create`, `resolve_output_path` |
| `git.ab` | `is_patch_already_applied`, `git_apply_patch`, `git_init`, `git_add`, `git_commit` |
| `fetch.ab` | `download_to`, `download_tmp` |
| `sudo.ab` | `sudo_cmd` |
| `pkg.ab` | `apt_install`, `apt_install_deb`, `npm_install`, `brew_install`, `curl_install` |

## Vendored Tools (`vendor/`)

All downloaded by `dependencies.sh` with SHA256 verification: amber 0.6.0-alpha, jq 1.8.2, jsonnet 0.22.0, minijinja-cli 2.21.0 (as `j2`), jsonschema 16.0.0, bashunit.
