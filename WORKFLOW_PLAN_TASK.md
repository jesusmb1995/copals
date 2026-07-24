# CI/CD Workflow Plan

## Goal
Automate Docker image build, test, and publish for `copals`.
- Developer only commits code. CI creates and pushes version tag after tests pass.
- PRs run tests against latest published image by default; optional `test-image:*` label selects specific version.
- Fresh image must pass tests before it is published.

## Workflows

### 1. Build, test, tag, push on VERSION bump (`.github/workflows/image.yml`)
Triggers: `push` to `main` with path filter `VERSION`.

Steps:
1. Checkout sources
2. Read `VERSION`
3. Build both variants: `copals-with-podman`, `copals-without-podman`
4. Test each built variant by mounting repo source into container:
   ```sh
   docker run --rm -v "$PWD:/work" -w /work <image> sh test.sh
   ```
5. If tests pass:
   - Login to GHCR (`packages: write`)
   - Tag and push both variants as `ghcr.io/<owner>/copals:<version>`
   - If `VERSION` is not a pre-release semver, also tag/push as `:latest`
6. If tests fail, do NOT tag or push. Workflow fails.

Tag flow: CI creates tag locally (`git tag v<x>`) and pushes it to remote. Developer never manually pushes tag.

### 2. PR test workflow (`.github/workflows/pr-test.yml`)
Triggers: `pull_request` (opened, synchronize, reopened, labeled, unlabeled).

Steps:
1. Checkout sources
2. Detect `test-image:*` label on PR
3. Pull specified image from GHCR if label present; otherwise pull `:latest`
4. Mount PR sources into container:
   ```sh
   docker run --rm -v "$PWD:/work" -w /work <image> sh test.sh
   ```
5. Post pass/fail result as PR comment
6. If `:latest` does not exist yet, fall back to `docker build --target copals-base` + test from source

## Constraints
- CI is the only actor that pushes tags. No manual tag push.
- Version tags exist on remote ONLY after CI passed.
- PR tests mount live PR sources; image provides runtime only.
- Two publishable variants: `copals-with-podman` and `copals-without-podman`.
- `:latest` promotion skipped for pre-release versions (e.g. `v0.2.0-prealpha`).
