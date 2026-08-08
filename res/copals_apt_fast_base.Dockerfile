# TODO doc limitation copals, this all works assuming debian target... what if another base image?
# TODO copals-apt-fast-base move to docker registry... and maintain there.
ARG BASE
FROM ${BASE} AS copals-apt-fast-base

# Pin sources to the same snapshot as the aria2 debs.
# Regenerate with: copals/res/gen-aria2-docker-section.sh
RUN echo "deb http://snapshot.debian.org/archive/debian/20260704T120000Z testing main" > /etc/apt/sources.list
RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99snapshot-valid-until

# ---BEGIN aria2 + ca-certificates (base TLS trust store) install---
# aria2: native arch so the base builds on amd64 and arm64 hosts.
# ca-certificates: its postinst runs update-ca-certificates, populating
# /etc/ssl/certs/ca-certificates.crt so every downstream repo/layer can do TLS
# (e.g. curl/github-binary installs in system_tools). Load-bearing — do not drop:
# without it curl fails with "(77) error adding trust anchors".
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends aria2 ca-certificates
# ---END aria2 + ca-certificates deps---

RUN rm -f /tmp/*.db

# ADD downloads apt-fast script (no external tools needed)
ADD https://raw.githubusercontent.com/ilikenwf/apt-fast/1f55b476b568f8589df8c040c2c1afd4a2384c4f/apt-fast /usr/local/sbin/apt-fast
ADD https://raw.githubusercontent.com/ilikenwf/apt-fast/1f55b476b568f8589df8c040c2c1afd4a2384c4f/apt-fast.conf  /etc/apt-fast.conf
RUN echo "4df71b8bba3d2553e3450833f6626560d5c5022e5866a6816b53f131c99904b2  /usr/local/sbin/apt-fast" | sha256sum --check \
 && echo "e545093738b6023cc4c811a0d253a3ddc99b45025d7cf6426133fe3d3c151fdc  /etc/apt-fast.conf" | sha256sum --check \
 && chmod +x /usr/local/sbin/apt-fast \
 && sed -i 's|^#_APTMGR=apt-get|_APTMGR=/usr/bin/apt-get|' /etc/apt-fast.conf

# Keep using snapshot list, that pins versions to that date and keep container stable/reproducible
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked  \
  apt-fast update
# update fetches faster than raw apt-get update
#RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
#  rm -f /etc/apt/sources.list.d/debian.sources \
#  && echo "deb http://deb.debian.org/debian testing main" > /etc/apt/sources.list  \
#  && apt-fast update \
#  && apt-fast upgrade -y

# eatmydata aims to speed disk giving up some safety/sync
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-fast install -y --no-install-recommends eatmydata
RUN ls /var/lib/apt/lists

# /usr/local/bin/apt-get wrapper: redirects to apt-fast, skips update if sources.list unchanged.
COPY gen-apt-wrapper.sh /tmp/gen-apt-wrapper.sh
RUN sh /tmp/gen-apt-wrapper.sh 337a9afe0c6514d5fd6e05c07704a193b1f90f578f4fe3731221d3d227ce4eaa && rm /tmp/gen-apt-wrapper.sh
