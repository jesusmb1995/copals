# Container Builds

## Dockerfiles

| File | Purpose |
|---|---|
| `deploy_bundle.Dockerfile` | Main bundle build. Takes `BASE`, `USERNAME`, `DEPLOYABLE_COPALS_BUNDLE`. Creates user, copies bundle, runs `./install.sh` with tmpfs/cache mounts for apt, npm, and brew locks. Defaults to unprivileged user. |
| `copals_apt_fast_base.Dockerfile` | Optimized Debian testing base with aria2, apt-fast, eatmydata. Pins snapshot.debian.org for reproducibility. Auto-generates aria2 dependency ADD/sha256 sections. |
| `copals_test_base.Dockerfile` | Minimal test tools base (xvfb, xdotool, imagemagick, jq) extracted into a scratch-layer image. |
| `deploy_test.Dockerfile` | Test runner image. Copies bashunit, test scripts, and meta.json. Layers tools from `copals-test-base`. CMD runs `run_tests.sh`. |

## Container Commands

- `container build <bundle_dir>` — builds image from generated bundle. `--reuse` updates an existing image in-place using `podman commit`.
- `container test <user_dir> <bundle_dir> [repo_id...]` — builds test container, runs bashunit tests (regular + screenshot), mounts golden/generated screenshot directories. Filters to specified repos or runs all from `meta.json`.
- `container launch-window <bundle_dir>` — starts Xephyr, runs i3 inside container.

## Runtime Support (`shlib/container.ab`)

Functions: `build_image`, `image_exists`, `remove_image`, `ensure_stop`, `update_container`. Default runtime is Podman.

## Snapshot Reproducibility

Scripts in `res/`:
- `gen-aria2-docker-section.sh` — regenerates ADD/sha256 section for a given debian snapshot timestamp.
- `gen-aria2-docker-section-update.sh` — in-place update of the Dockerfile's auto-generated section.
- `gen-apt-wrapper.sh` — generates `/usr/local/bin/apt-get` wrapper with pinned expected sources hash.
