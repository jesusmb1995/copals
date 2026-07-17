# Advanced Usage

## Custom Presets

Config presets live in `{user_dir}/config-presets/{name}.jsonnet` or `.json`. They are rendered through Jsonnet, validated against `config.schema.json`, and control every aspect of generation: base image, packages (apt, brew, npm), dotfiles, AI tools, browsers, languages, system tools, and repositories.

## Multi-Profile Builds

The `shard` command generates, builds, and tests selected repos in isolation:

```
copals shard <user_dir> <jsonnet_config> <id> [<id>...]
```

It filters the config to only include specified repo IDs (via `shard.jsonnet`), builds each as a layered dependency using `deploy_bundle.Dockerfile`, and runs container tests on the final bundle.

During development its also fast to build your whole image once, and then use `shard reuse` to install and test individual repo by modifying existing running image. This alows to do live editing/development.

## CI Pipeline

The `pipeline` command runs generate → container build → container test in sequence:

```
copals pipeline <user_dir> <jsonnet_config> <bundle_dir>
```

Supports `-f`/`--force` for generate and `--reuse` for container build.

## Fetching User Repos (`user-clone`)

Repos declared with `clone: true` and a `url` in `repos.libsonnet` are not
bundled with copals — they must be cloned from their remote before generation
can process them. The `user-clone` command handles this:

```
copals user-clone <user_dir> <config_name>
```

It runs **on the host** (never inside the container) so that your local git
credentials, SSH keys, and credential helpers are used for private repos. The
copals container is used only to render the jsonnet config and extract repo
metadata; the actual `git clone` executes here.

Typical workflow:

```
# 1. Clone repos (run once, repos persist under user/repos/)
copals user-clone user config_personal

# 2. Generate + build + test
copals pipeline user config_personal /tmp/bundle
```

### Git Credentials for Private Repos

`user-clone` uses whatever git authentication is already configured on your
host. Ensure you can clone private repos manually first:

```
git clone https://github.com/yourorg/your-private-repo.git /tmp/test
```

If that prompts for a password, set up one of:

- **HTTPS with credential helper** (recommended):
  ```
  git config --global credential.helper osxkeychain   # macOS
  git config --global credential.helper store          # Linux
  ```
  Then clone once interactively — credentials are cached for future clones.

- **SSH keys**: use SSH URLs in `repos.libsonnet` (`url: 'git@github.com:...'`)
  and ensure your SSH key is added to GitHub and `ssh-agent`.

## Content Caching

During generation each repository is content-hashed (SHA256 of directory + `impl` choice). If unchanged, rsync is skipped. State files are stored under `~/.cache/jbdt-process-repo/generate_state/`.

## Install Modes

- `install.sh local [prefix]` — installs to `<prefix>/lib/copals/` and `<prefix>/bin/copals`. Default prefix: `/usr`.
- `install.sh podman [args...]` — builds `copals:dev` container image.

## Container Launch

- `container launch-window` — starts Xephyr on display `:2`, caps resolution at 1680×1050, runs i3 inside container via podman.
- `launch_native_i3_vt.sh` — companion script for GPU-accelerated second Xorg on a separate VT.

## Optimized Base Image

When `base_image` matches `*debian:testing*`, copals builds an intermediate `copals-apt-fast-base` image with aria2, apt-fast, eatmydata, and a custom `/usr/local/bin/apt-get` wrapper that delegates `install`/`update` to apt-fast/eatmydata and skips redundant `apt-get update` calls.

## Entrypoint Modes (`copals.sh`)

- **Container** — if podman is installed and `copals:dev` image exists, runs inside container (bind-mounted at PWD).
- **Local** — compiles `.ab` via vendored amber, then executes.
- **Force local** — set `COPALS_RUN=local`.

## Jinja2 Templating

All `*.j2` files in the destination tree are rendered after repo processing using the validated config JSON as context.
