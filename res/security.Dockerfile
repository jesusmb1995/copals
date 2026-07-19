# copals:security — minimal glibc image with brew + the three audit tools.
#
# Brew needs glibc, so this is debian-based (the main copals:dev image is Alpine
# and cannot run Linuxbrew). The tools are installed through the shared
# `dependencies.sh --extensions` so a host user can install the exact same set
# locally with `install.sh extensions` (or `dependencies.sh --extensions`).
#
# Build with:  install.sh security
# Used by:     `copals generate ... --audit` (run via copals.sh on the host)
#
# Build context is the copals/ directory (see install.sh install_security).

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        procps \
        coreutils \
        passwd \
    && rm -rf /var/lib/apt/lists/*

# Linuxbrew bootstrap. NONINTERACTIVE=1 keeps the build from prompting.
RUN NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Make brew-installed binaries visible at runtime (every RUN layer and the
# final ENTRYPOINT inherit this PATH).
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# Install semgrep + trufflehog + clamav via the shared extensions installer.
COPY dependencies.sh /tmp/dependencies.sh
RUN sh /tmp/dependencies.sh --extensions && rm -f /tmp/dependencies.sh

# clamav needs a freshclam.conf (the brew package only ships .sample) and a
# clamav user to drop privileges to. Bake a populated signature DB into the
# image so audits work offline; the audit runner still refreshes at runtime
# when network is available.
RUN groupadd -r clamav 2>/dev/null || true \
    && useradd -r -g clamav -s /usr/sbin/nologin -d /nonexistent clamav 2>/dev/null || true \
    && mkdir -p /home/linuxbrew/.linuxbrew/var/lib/clamav \
    && chown -R clamav:clamav /home/linuxbrew/.linuxbrew/var/lib/clamav \
    && printf 'DatabaseMirror database.clamav.net\n' \
        > /home/linuxbrew/.linuxbrew/etc/clamav/freshclam.conf \
    && chown clamav:clamav /home/linuxbrew/.linuxbrew/etc/clamav/freshclam.conf \
    && su clamav -s /bin/sh -c "freshclam --quiet"

# The audit runner (semgrep + trufflehog + clamav over a directory). Mounted
# bundle dirs are scanned by invoking this as the entrypoint.
COPY res/audit.sh /usr/local/bin/copals-audit
RUN chmod +x /usr/local/bin/copals-audit

ENTRYPOINT ["copals-audit"]
