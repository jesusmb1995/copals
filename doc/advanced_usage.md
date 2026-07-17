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

`container launch-window <image[:tag]>` launches i3 inside the container and
shows it on the host. The transport is chosen by host OS:

- **Linux** — starts Xephyr on display `:2` (caps resolution at 1680×1050), runs
  i3 inside the container via a shared `/tmp/.X11-unix` socket (software
  rendering).
- **macOS** — runs Xvfb + i3 + x11vnc inside the container and serves VNC on the
  host loopback. The launcher auto-opens **TigerVNC** (`vncviewer`). Software
  rendering only — the podman machine VM (applehv) exposes no GPU to Linux
  guests. Flags: `--geometry WxHxD` (default `1680x1050x24`),
  `--port N` (default `5900`, published on `127.0.0.1:<port>`).

The launched image must contain `x11vnc`, `xvfb`, and `x11-xserver-utils`
(provided by the UI apt install hook, `install_apt_essential_ui.ab.j2`).

### macOS: one-time VNC client install

macOS 26 (Tahoe) Screen Sharing **no longer speaks plain VNC**, so `open
vnc://…` does not work. Install a real VNC client:

```
brew install --cask tigervnc-viewer
```

This provides `/Applications/TigerVNC.app/Contents/MacOS/vncviewer`. The
`launch-window` command auto-opens it; if it is missing it prints the install
command and the manual connect line instead.

### macOS: usage

```
copals container launch-window jberlanga-devtools:latest
# or with flags:
copals container launch-window jberlanga-devtools:latest --geometry 1280x800x24 --port 5901
```

The launcher starts the container, waits for the VNC server, opens TigerVNC to
`127.0.0.1::<port>` (note the **double colon** = raw port), and blocks. **Close
the TigerVNC window** (or Ctrl-C the launcher) to stop and auto-remove the
container.

### macOS: exact commands that work

One-time, host side — install the VNC client:
```
brew install --cask tigervnc-viewer
```

Build the image (so it contains `x11vnc`/`xvfb`/`x11-xserver-utils` from the UI
apt hook), then launch:
```
copals generate user config_gpersonal jberlanga-devtools
copals container build jberlanga-devtools
copals container launch-window jberlanga-devtools:latest
```
Flags: `--geometry 1280x800x24 --port 5901`. Connect with TigerVNC to
`127.0.0.1::<port>` (double colon = raw port). Close the viewer to tear down.

Manual fallback (equivalent to what the launcher does):
```
podman run -d --rm --name vncmanual \
  -p 127.0.0.1:5940:5900 \
  -e DISPLAY=:0 -e LIBGL_ALWAYS_SOFTWARE=1 -e HOME=/home/user --user=1000 \
  --entrypoint /bin/bash \
  jberlanga-devtools:latest -c \
  'rm -f /tmp/.X0-lock /tmp/.X11-unix/X0; Xvfb :0 -screen 0 1280x800x24 >/tmp/xvfb.log 2>&1 & sleep 1; DISPLAY=:0 xsetroot -solid grey 2>/dev/null || true; DISPLAY=:0 i3 >/tmp/i3.log 2>&1 & sleep 1; trap "pkill Xvfb 2>/dev/null; pkill i3 2>/dev/null; pkill x11vnc 2>/dev/null" EXIT INT TERM; DISPLAY=:0 exec x11vnc -display :0 -forever -nopw -rfbport 5900 -fixscreen 5'
/Applications/TigerVNC.app/Contents/MacOS/vncviewer 127.0.0.1::5940
# teardown:
podman rm -f vncmanual
```

Gotchas that break it (learned the hard way):
1. macOS 26 Screen Sharing does **not** speak plain VNC — `open vnc://…` fails.
   Use TigerVNC. TigerVNC 1.16 has **no F8** menu key (and F8 is the macOS
   Play/Pause media key); use the Ctrl+Alt shortcuts above.
2. x11vnc needs `-fixscreen 5` (or similar) or the first frame stays black.
3. **Do not** run `podman rm`/`pkill` on the container or viewer while the viewer
   is open — that drops the session and causes "attempt to reconnect" popups.
4. Connect with the **double-colon** form `vncviewer 127.0.0.1::5940`
   (`::port` = raw port; single `:N` means VNC display N → port 5900+N).

### macOS: keyboard / input (TigerVNC 1.16 — NOT F8)

TigerVNC 1.16 removed the old F8 menu key. On a Mac, F8 is also the media
Play/Pause key, so never use it. The 1.16 controls are **Ctrl+Alt** based:

- **Ctrl+Alt+G** — grab the keyboard so i3 Super/Alt shortcuts reach the remote.
- **Ctrl+Alt+Enter** — toggle full-screen.
- **Ctrl+Alt+M** — open the viewer menu (options, quit).
- **Ctrl+Alt** (alone) — release the keyboard back to macOS.
- **Ctrl+Alt+Space** — temporarily send that combo to i3.

i3 `$mod` mapping on macOS (TigerVNC swaps modifiers): CmdL→AltL, CmdR→SuperL
("win"). So if the i3 config uses Mod4 (Super), press **Right-Cmd** for `$mod`.

To stop the Mac top row from sending media keys (optional): System Settings →
Keyboard → enable "Use F1, F2, etc. keys as standard function keys". With
TigerVNC 1.16 you don't need F-keys at all.

- `launch_native_i3_vt.sh` — companion script for GPU-accelerated second Xorg on
  a separate VT (Linux only; macOS podman VM has no GPU).

## Optimized Base Image

When `base_image` matches `*debian:testing*`, copals builds an intermediate `copals-apt-fast-base` image with aria2, apt-fast, eatmydata, and a custom `/usr/local/bin/apt-get` wrapper that delegates `install`/`update` to apt-fast/eatmydata and skips redundant `apt-get update` calls.

## Entrypoint Modes (`copals.sh`)

- **Container** — if podman is installed and `copals:dev` image exists, runs inside container (bind-mounted at PWD).
- **Local** — compiles `.ab` via vendored amber, then executes.
- **Force local** — set `COPALS_RUN=local`.

## Jinja2 Templating

All `*.j2` files in the destination tree are rendered after repo processing using the validated config JSON as context.
