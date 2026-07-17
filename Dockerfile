ARG ALPINE_VERSION=3.22.5
ARG PODMAN_STAGE=copals-with-podman

FROM curlimages/curl:8.21.0 AS downloader
USER root
RUN apk add --no-cache xz bash
COPY dependencies.sh /tmp/dependencies.sh
COPY vendor/bashunit_installer/install_bashunit.sh /tmp/vendor/bashunit_installer/install_bashunit.sh
RUN ["/bin/sh", "/tmp/dependencies.sh", "/tmp/vendor"]

# podman-remote: static binary, zero daemon deps.
# Downloaded separately so it doesn't bloat the vendor/ tree.
RUN curl -fSL# -o /tmp/podman-remote.tar.gz \
    "https://github.com/containers/podman/releases/download/v6.0.1/podman-remote-static-linux_amd64.tar.gz" \
    && echo "f9e286224269e1db91892a9fceda92f844046ab5118f65dd815ab387cae24c6d  /tmp/podman-remote.tar.gz" | sha256sum -c - \
    && tar xzf /tmp/podman-remote.tar.gz -C /tmp/ \
    && mv /tmp/bin/podman-remote-static-linux_amd64 /tmp/podman \
    && rm -rf /tmp/podman-remote.tar.gz /tmp/bin

FROM alpine:${ALPINE_VERSION} AS builder
COPY . /copals/
COPY --from=downloader /tmp/vendor /copals/vendor
RUN ["/bin/sh", "/copals/install.sh", "local"]

# TODO REVIEW: minimal approach would be to download zip directly rather than git clone
FROM alpine:${ALPINE_VERSION} AS copals-base
# TODO: replace full git with a minimal git-clone client (e.g. libgit2 or a
# static busybox-git) to shrink the image. Full apk git is ~20 MiB.
RUN --mount=type=cache,target=/var/cache/apk/ \
    apk add --no-cache rsync bash curl git
COPY --from=builder /usr/bin/copals /usr/bin/copals
COPY --from=builder /usr/lib/copals /usr/lib/copals

FROM copals-base AS copals-with-podman
COPY --from=downloader /tmp/podman /usr/bin/podman

FROM copals-base AS copals-without-podman

FROM ${PODMAN_STAGE}
ENTRYPOINT ["copals"]
CMD ["help"]
