ARG BASE
FROM ${BASE}

USER root

ARG USERNAME=user
ARG DEPLOYABLE_COPALS_BUNDLE

ENV HOME=/home/${USERNAME}
ENV WINIT_UNIX_BACKEND=x11
ENV PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"

RUN useradd --create-home --shell /bin/bash "${USERNAME}" || true
ENV USERNAME=${USERNAME}

WORKDIR ${HOME}

COPY --chown=${USERNAME}:${USERNAME} \
  ${DEPLOYABLE_COPALS_BUNDLE} \
  "${HOME}/${DEPLOYABLE_COPALS_BUNDLE}"

WORKDIR ${HOME}/${DEPLOYABLE_COPALS_BUNDLE}
# Brew needs a tmpfs for lock files (overlayfs filename length issue).
# /tmp as tmpfs ensures no apt-fast.lock from previous layer persists.
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/tmp/brew-locks \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/home/${USERNAME}/.npm,sharing=locked \
    ./install.sh

# Fix ownership: install.sh runs as root, ensure the user owns its home.
# Keep .homebrew owned by root so brew --reuse (run as root) can write to it.
# Split into separate RUN layers so Docker cannot coalesce them with the
# install.sh layer cache; otherwise an older cached layer can keep .config
# (created by install) as root-owned and the chown never re-applies.
RUN chown -R ${USERNAME}:${USERNAME} ${HOME}
RUN chown -R root:root ${HOME}/.homebrew 2>/dev/null || true

# Default to the unprivileged user so x11docker/distrobox/podman run as "user"
# rather than root, with the fully-configured /home/${USERNAME}.
USER ${USERNAME}
