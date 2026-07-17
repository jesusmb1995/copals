ARG ALPINE_VERSION=3.22.5

FROM curlimages/curl:8.21.0 AS downloader
USER root
RUN apk add --no-cache xz bash
COPY dependencies.sh /tmp/dependencies.sh
COPY vendor/bashunit_installer/install_bashunit.sh /tmp/vendor/bashunit_installer/install_bashunit.sh
RUN ["/bin/sh", "/tmp/dependencies.sh", "/tmp/vendor"]

FROM alpine:${ALPINE_VERSION} AS builder
COPY . /copals/
COPY --from=downloader /tmp/vendor /copals/vendor
RUN ["/bin/sh", "/copals/install.sh", "local"]

FROM alpine:${ALPINE_VERSION}
RUN --mount=type=cache,target=/var/cache/apk/ \
    apk add --no-cache rsync bash podman containers-common
COPY --from=builder /usr/bin/copals /usr/bin/copals
COPY --from=builder /usr/lib/copals /usr/lib/copals
ENTRYPOINT ["copals"]
CMD ["help"]
