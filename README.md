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
 -

## Advanced Usage

For advanced topics, see the documentation in the [`doc/`](doc/) directory:

- [Advanced Usage](doc/advanced_usage.md) – custom presets, multi-profile builds, and CI integration
- [Hooks](doc/hooks.md) – generation hooks for pre-fetching sources and auditing
- [Container Builds](doc/container_builds.md) – fully isolated builds with podman/Docker
- [Customization](doc/customization.md) – extending the schema, adding new package types, and writing your own Amber templates
