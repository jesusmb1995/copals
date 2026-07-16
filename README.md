# Copals

![Copals](doc/copals_banner.png)

Copals is a simple yet flexible approach to managing all your packages and configurations and easily deploy them. For example, you can use it to have a single place/repo where you modify all your Linux development setup (installation of AI tools, skills, neovim configuration, etc.). Copals heavily leverages Amber language which compiles into bash and optionally `podman` for consistent installation and testing.a

> [!NOTICE]
> Even though you can theoreticaly easily deploy into non-debian distributions. Currently the framework is tuned heavily for debian:testing target. Including the podman images used for testing. 

## Core Features
- Bundle all your configuration (installed packages, dot files, ...) in a single `install.sh`.
- Bundle can execute on bash without any required dependencies
- Bundle can be generated with minimal dependencies. Mandatory dependencies are provided in alpine container under 50 MB (uncompressed).
- Install file is easily auditable (e.g. for security concerns). By using "generation hooks" you can pull sources ahead of time instead of installing from remotes at deploy time.
- Provides necessary plumbing to develop and test new configurations.

## Why Copals? (vs. Ansible, Stow, Chezmoi)

While tools like Ansible, GNU Stow, and chezmoi offer configuration management, Copals differs in several key aspects:

- **Zero Runtime Dependencies**: Unlike chezmoi (which requires Go or precompiled binaries) or GNU Stow (which requires Perl), Copals transpiles down to pure POSIX-compliant Bash using the Amber programming language. At install-time, the target environment needs nothing but `bash`.
- **Integrated Container Testing**: Copals bridges the gap between dotfiles and system provisioning by offering integrated Podman/Docker container-based testing (`copals shard`). Tests for your packages and hooks are compiled and asserted cleanly in an isolated system prior to deploying to your host.
- **Pre-fetch & Audit Pipeline**: By utilizing compile-time Jinja2 rendering and generation hooks, administrators can resolve assets, binaries, and configurations ahead of time. The output is a single, self-contained, auditable `install.sh`.

## Future Work
- **Stow-like Amber Manager (`stowerab`)**: Develop a lightweight, Stow-compatible dotfile symlink manager written natively in Amber, integrating it directly into the Copals workflow to manage simple files without scattering configurations.
- **Shareable & Modular Plugin System**: Design a mechanism to easily import, share, and reuse configurations and hooks from other users' repositories.
- **Multi-OS & Package Manager Support**: Expand tests, hooks, and built-in scripts to support other operating systems (e.g., macOS, Alpine, Arch) and alternative package managers.

## Basic Usage

> [!WARNING]
> Current version is pre-alpha and very experimental.

```
curl https://raw.githubusercontent.com/jesusmb1995/copals/main/install.sh | sh -s podman
curl -LO https://raw.githubusercontent.com/jesusmb1995/copals/main/copals.sh
# Place copals.sh next to your config
sh copals.sh build my_config_dir preset_name dest_dir
```

Where `my_config_dir` has the following structure:

```
my_config_dir/
├── config-presets/          # Jsonnet/JSON build presets
│   └── my_preset.jsonnet
├── repo-hooks/              # Amber hooks per repo (generate_*, install_*)
│   ├── generate_<repo_id>.ab
│   └── install_<repo_id>.ab
├── repos/                   # Source config directories
│   └── <repo_id>/
└── tests/                   # Optional integration tests
    └── ...
```

## Advanced Usage

For advanced topics, see the documentation in the [`doc/`](doc/) directory:

- [Advanced Usage](doc/advanced_usage.md) – custom presets, multi-profile builds, and CI integration
- [Hooks](doc/hooks.md) – generation hooks for pre-fetching sources and auditing
- [Container Builds](doc/container_builds.md) – fully isolated builds with podman/Docker
- [Customization](doc/customization.md) – extending the schema, adding new package types, and writing your own Amber templates
